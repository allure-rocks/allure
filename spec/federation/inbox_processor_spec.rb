# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Inbox::Processor do
  let(:recipient) { create(:local_actor) }
  let(:remote) { create(:actor, uri: "https://remote.example/users/demo") }
  let(:activity_id) { "https://remote.example/activities/#{SecureRandom.uuid}" }

  def inbox_item(activity, type: nil)
    type ||= activity.fetch("type")
    create(
      :federation_inbox_item,
      recipient_actor: recipient,
      activity_uri: activity.fetch("id"),
      activity_type: type,
      actor_uri: activity.fetch("actor"),
      raw: activity
    )
  end

  before do
    remote.update!(public_key_id: "#{remote.uri}#main-key", public_key_pem: "remote public key")
  end

  it "records a valid Follow as a pending request without emitting Accept" do
    item = inbox_item({
      "id" => activity_id,
      "type" => "Follow",
      "actor" => remote.uri,
      "object" => recipient.uri
    })

    expect {
      Federation::ProcessInboxItemJob.perform_now(item)
    }.to change(Following, :count).by(1)

    following = Following.find_by!(uri: activity_id)
    expect(following).to be_pending
    expect(item.reload).to be_processed
    expect(FederationOutboxEvent.where(activity_type: "Accept")).to be_empty
  end

  it "notifies the recipient of the inbound follow request" do
    item = inbox_item({
      "id" => activity_id,
      "type" => "Follow",
      "actor" => remote.uri,
      "object" => recipient.uri
    })

    expect {
      Federation::ProcessInboxItemJob.perform_now(item)
    }.to change { Notification.where(user: recipient.user, kind: "follow_request").count }.by(1)
  end

  it "resets a rejected follow request to pending on a new Follow" do
    following = create(
      :following, :rejected, follower_actor: remote, followed_actor: recipient,
      uri: "https://remote.example/activities/follow-old"
    )
    item = inbox_item({
      "id" => activity_id,
      "type" => "Follow",
      "actor" => remote.uri,
      "object" => recipient.uri
    })

    Federation::ProcessInboxItemJob.perform_now(item)

    expect(following.reload).to be_pending
    expect(following.uri).to eq(activity_id)
  end

  # The follower unfollowed while this instance could not hear its Undo (a
  # domain change, an outage): its new Follow must be answered, not ignored.
  it "accepts again an accepted follower's Follow under a new id" do
    following = create(
      :following, :accepted, follower_actor: remote, followed_actor: recipient,
      uri: "https://remote.example/activities/follow-old"
    )
    item = inbox_item({ "id" => activity_id, "type" => "Follow", "actor" => remote.uri, "object" => recipient.uri })

    expect { Federation::ProcessInboxItemJob.perform_now(item) }.not_to change(Following, :count)

    expect(following.reload).to be_accepted
    expect(following.uri).to eq(activity_id)
    accept = FederationOutboxEvent.find_by!(activity_type: "Accept")
    expect(accept.payload["object"]).to eq(activity_id)
    expect(accept.audience["to"]).to eq([ remote.uri ])
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued.with(accept)
    expect(Notification.where(kind: "follow_request")).to be_empty
  end

  it "keeps a pending request under the follower's newest Follow id" do
    following = create(
      :following, follower_actor: remote, followed_actor: recipient,
      uri: "https://remote.example/activities/follow-old"
    )
    item = inbox_item({ "id" => activity_id, "type" => "Follow", "actor" => remote.uri, "object" => recipient.uri })

    Federation::ProcessInboxItemJob.perform_now(item)

    expect(following.reload).to be_pending
    expect(following.uri).to eq(activity_id)
    expect(FederationOutboxEvent.where(activity_type: "Accept")).to be_empty
  end

  it "answers nothing new to a redelivered Follow" do
    create(:following, :accepted, follower_actor: remote, followed_actor: recipient, uri: activity_id)
    item = inbox_item({ "id" => activity_id, "type" => "Follow", "actor" => remote.uri, "object" => recipient.uri })

    Federation::ProcessInboxItemJob.perform_now(item)

    expect(FederationOutboxEvent.where(activity_type: "Accept")).to be_empty
  end

  it "terminally rejects a follow from a blocked actor" do
    create(:federation_actor_block, actor_uri: remote.uri)
    item = inbox_item({
      "id" => activity_id,
      "type" => "Follow",
      "actor" => remote.uri,
      "object" => recipient.uri
    })

    expect { Federation::ProcessInboxItemJob.perform_now(item) }.not_to change(Following, :count)
    expect(item.reload).to be_rejected
  end

  it "terminally rejects activity from a blocked authority" do
    create(:federation_domain_block, domain: "remote.example")
    item = inbox_item({
      "id" => activity_id,
      "type" => "Follow",
      "actor" => remote.uri,
      "object" => recipient.uri
    })

    expect { Federation::ProcessInboxItemJob.perform_now(item) }.not_to change(Following, :count)
    expect(item.reload).to be_rejected
  end

  it "rejects an inbound Reject for a known pending request" do
    following = create(:following, follower_actor: recipient, followed_actor: remote, uri: activity_id)
    item = inbox_item({
      "id" => "https://remote.example/activities/reject-1",
      "type" => "Reject",
      "actor" => remote.uri,
      "object" => following.uri
    })

    Federation::ProcessInboxItemJob.perform_now(item)

    expect(following.reload).to be_rejected
    expect(item.reload).to be_processed
  end

  # Mastodon removes a follower by rejecting its accepted Follow.
  it "ends an accepted follow its owner rejects, withdrawing what it delivered" do
    following = create(:following, :accepted, follower_actor: recipient, followed_actor: remote, uri: activity_id)
    note = create(:remote_note, actor: remote, audience: "followers")
    entitlement = create(:remote_note_recipient, remote_note: note, recipient_actor: recipient)
    item = inbox_item({
      "id" => "https://remote.example/activities/reject-accepted",
      "type" => "Reject",
      "actor" => remote.uri,
      "object" => following.uri
    })

    Federation::ProcessInboxItemJob.perform_now(item)

    expect(following.reload).to be_undone
    expect(entitlement.reload).to be_withdrawn
    expect(item.reload).to be_processed
  end

  it "withdraws the local follower's entitlements when the follow is rejected" do
    following = create(:following, follower_actor: recipient, followed_actor: remote, uri: activity_id)
    note = create(:remote_note, actor: remote, audience: "followers")
    attachment = create(:remote_note_attachment, remote_note: note, status: "cached")
    entitlement = create(:remote_note_recipient, remote_note: note, recipient_actor: recipient)
    item = inbox_item({
      "id" => "https://remote.example/activities/reject-1",
      "type" => "Reject",
      "actor" => remote.uri,
      "object" => following.uri
    })

    Federation::ProcessInboxItemJob.perform_now(item)

    expect(following.reload).to be_rejected
    expect(entitlement.reload).to be_withdrawn
    expect(entitlement.withdrawal_reason).to eq("rejected")
    expect(attachment.reload).to be_purged
  end

  it "withdraws and purges an entitled remote course when the follow is rejected" do
    following = create(:following, follower_actor: recipient, followed_actor: remote, uri: activity_id)
    segment = create(:remote_segment, actor: remote, audience: "followers")
    segment_attachment = create(:remote_segment_attachment, remote_segment: segment, status: "cached")
    entitlement = create(:remote_segment_recipient, remote_segment: segment, recipient_actor: recipient)
    item = inbox_item({
      "id" => "https://remote.example/activities/reject-2",
      "type" => "Reject",
      "actor" => remote.uri,
      "object" => following.uri
    })

    Federation::ProcessInboxItemJob.perform_now(item)

    expect(entitlement.reload).to be_withdrawn
    expect(entitlement.withdrawal_reason).to eq("rejected")
    expect(segment_attachment.reload).to be_purged
    expect(segment.reload).to be_location_data_purged
  end

  it "rejects a Follow addressed to another local actor" do
    item = inbox_item({
      "id" => activity_id,
      "type" => "Follow",
      "actor" => remote.uri,
      "object" => "http://allure.test:3000/users/another"
    })

    expect { Federation::ProcessInboxItemJob.perform_now(item) }.not_to change(Following, :count)
    expect(item.reload).to be_rejected
  end

  it "accepts an inbound Accept only for the matching pending Follow" do
    following = create(
      :following,
      follower_actor: recipient,
      followed_actor: remote,
      uri: "http://allure.test:3000/activities/follow-outbound"
    )
    item = inbox_item({
      "id" => activity_id,
      "type" => "Accept",
      "actor" => remote.uri,
      "object" => following.uri
    })

    Federation::ProcessInboxItemJob.perform_now(item)

    expect(following.reload).to be_accepted
    expect(item.reload).to be_processed
  end

  it "notifies the local follower when a remote Accept arrives" do
    following = create(
      :following,
      follower_actor: recipient,
      followed_actor: remote,
      uri: "http://allure.test:3000/activities/follow-outbound"
    )
    item = inbox_item({
      "id" => activity_id,
      "type" => "Accept",
      "actor" => remote.uri,
      "object" => following.uri
    })

    expect {
      Federation::ProcessInboxItemJob.perform_now(item)
    }.to change { Notification.where(user: recipient.user, kind: "follow_accepted").count }.by(1)

    expect(Notification.find_by!(user: recipient.user, kind: "follow_accepted").actor).to eq(remote)
  end

  it "undoes a remote Follow" do
    following = create(:following, :accepted, follower_actor: remote, followed_actor: recipient)
    item = inbox_item({
      "id" => activity_id,
      "type" => "Undo",
      "actor" => remote.uri,
      "object" => { "type" => "Follow", "id" => following.uri }
    })

    Federation::ProcessInboxItemJob.perform_now(item)

    expect(following.reload).to be_undone
    expect(item.reload).to be_processed
  end

  it "withdraws the request notification when the remote follow is undone" do
    following = create(:following, follower_actor: remote, followed_actor: recipient)
    notification = create(:notification, user: recipient.user, actor: remote, subject: following)
    item = inbox_item({
      "id" => activity_id,
      "type" => "Undo",
      "actor" => remote.uri,
      "object" => { "type" => "Follow", "id" => following.uri }
    })

    Federation::ProcessInboxItemJob.perform_now(item)

    expect(Notification.where(id: notification.id)).not_to exist
  end

  it "stores a Like only for a viewable local publication" do
    workout = create(:workout)
    Federation::ActorProvisioner.new(user: workout.user).call!
    publication = create(:workout_publication, workout:)
    item = inbox_item({
      "id" => activity_id,
      "type" => "Like",
      "actor" => remote.uri,
      "object" => publication.object_uri
    })

    expect { Federation::ProcessInboxItemJob.perform_now(item) }.to change(Reaction, :count).by(1)
    expect(item.reload).to be_processed
    expect(Reaction.last.audience).to eq("public")
  end

  # Followers publications fail closed for Like targets while restricted
  # federation is off (docs/dev/PUBLISHING.md).
  it "rejects a Like on a followers publication even from an accepted follower while restricted federation is off" do
    workout = create(:workout)
    owner = Federation::ActorProvisioner.new(user: workout.user).call!
    publication = create(:workout_publication, :with_followers, workout:)
    create(:following, :accepted, follower_actor: remote, followed_actor: owner)
    item = inbox_item({
      "id" => activity_id,
      "type" => "Like",
      "actor" => remote.uri,
      "object" => publication.object_uri
    })

    expect { Federation::ProcessInboxItemJob.perform_now(item) }.not_to change(Reaction, :count)
    expect(item.reload).to be_rejected
  end

  # docs/dev/REACTIONS.md: a Like keeps the audience of the publication it
  # reached, so its author is named only to the readers of that audience.
  it "records the audience of the publication a Like reached" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    workout = create(:workout)
    owner = Federation::ActorProvisioner.new(user: workout.user).call!
    publication = create(:workout_publication, :with_followers, workout:)
    remote.update!(capability_profile: "restricted_fetch")
    create(:following, :accepted, follower_actor: remote, followed_actor: owner)
    item = inbox_item({
      "id" => activity_id,
      "type" => "Like",
      "actor" => remote.uri,
      "object" => publication.object_uri
    })

    expect { Federation::ProcessInboxItemJob.perform_now(item) }.to change(Reaction, :count).by(1)
    expect(Reaction.last.audience).to eq("followers")
  end

  it "stores the Allure reaction type and notifies the owner" do
    workout = create(:workout)
    Federation::ActorProvisioner.new(user: workout.user).call!
    publication = create(:workout_publication, workout:)
    item = inbox_item({
      "id" => activity_id,
      "type" => "Like",
      "actor" => remote.uri,
      "object" => publication.object_uri,
      "_allure_reaction" => "beer"
    })

    expect {
      Federation::ProcessInboxItemJob.perform_now(item)
    }.to change(Reaction, :count).by(1)
      .and change { Notification.where(user: workout.user, kind: "reaction").count }.by(1)

    expect(Reaction.last.kind).to eq("beer")
    expect(Notification.last.actor).to eq(remote)
    expect(item.reload).to be_processed
  end

  # An external peer (Wanderer, Mastodon) sends a plain Like, and a buggy peer
  # may send an unknown value: both mean the neutral type, never a rejection.
  it "falls back to the neutral type for an external or unknown Like type" do
    workout = create(:workout)
    publication = create(:workout_publication, workout:)
    item = inbox_item({
      "id" => activity_id,
      "type" => "Like",
      "actor" => remote.uri,
      "object" => publication.object_uri,
      "_allure_reaction" => "wine"
    })

    expect { Federation::ProcessInboxItemJob.perform_now(item) }.to change(Reaction, :count).by(1)
    expect(Reaction.last.kind).to eq("like")
  end

  it "withdraws the like and its notification on Undo(Like)" do
    workout = create(:workout)
    Federation::ActorProvisioner.new(user: workout.user).call!
    publication = create(:workout_publication, workout:)
    like_uri = "https://remote.example/activities/like-#{SecureRandom.uuid}"
    Federation::ProcessInboxItemJob.perform_now(inbox_item({
      "id" => like_uri,
      "type" => "Like",
      "actor" => remote.uri,
      "object" => publication.object_uri,
      "_allure_reaction" => "coffee"
    }))
    reaction = Reaction.find_by!(uri: like_uri)

    undo = inbox_item({
      "id" => "https://remote.example/activities/undo-#{SecureRandom.uuid}",
      "type" => "Undo",
      "actor" => remote.uri,
      "object" => { "type" => "Like", "id" => like_uri }
    })
    expect {
      Federation::ProcessInboxItemJob.perform_now(undo)
    }.not_to change(Reaction, :count)

    expect(reaction.reload).not_to be_active
    expect(Notification.where(user: workout.user, kind: "reaction")).to be_empty
    expect(undo.reload).to be_processed
  end

  it "rejects unsupported activity types without retrying" do
    item = inbox_item({
      "id" => activity_id,
      "type" => "Announce",
      "actor" => remote.uri,
      "object" => "https://remote.example/activities/other"
    })

    Federation::ProcessInboxItemJob.perform_now(item)

    expect(item.reload).to be_rejected
    expect(item.attempts).to eq(1)
  end

  it "processes an embedded public Create into a received note and queues media" do
    activity = federation_note_activity
    item = inbox_item(activity)
    create(:following, :accepted, follower_actor: recipient, followed_actor: remote)

    expect { Federation::ProcessInboxItemJob.perform_now(item) }
      .to change(RemoteNote, :count).by(1)
      .and have_enqueued_job(Federation::FetchRemoteNoteAttachmentJob)

    note = RemoteNote.last
    expect(note).to be_active
    expect(note.entitled_to?(recipient)).to be(true)
    expect(item.reload).to be_processed
  end

  it "processes a Delete into a durable tombstone" do
    note = create(:remote_note, actor: remote, object_uri: "https://remote.example/api/v1/trail/abc")
    item = inbox_item(federation_delete_activity)

    Federation::ProcessInboxItemJob.perform_now(item)

    expect(note.reload).to be_deleted
    expect(item.reload).to be_processed
  end

  it "rejects Update with a distinct terminal reason" do
    item = inbox_item({
      "id" => activity_id,
      "type" => "Update",
      "actor" => remote.uri,
      "object" => { "id" => "https://remote.example/api/v1/trail/abc" }
    })

    Federation::ProcessInboxItemJob.perform_now(item)

    expect(item.reload).to be_rejected
    expect(item.last_error).to match(/Delete then Create/)
  end
end
