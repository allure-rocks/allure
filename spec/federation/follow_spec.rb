# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Follow do
  let(:user) { create(:user, username: "marie") }
  let(:remote) do
    create(
      :actor,
      uri: "https://wanderer.example/users/demo",
      public_key_id: "https://wanderer.example/users/demo#main-key",
      public_key_pem: "remote public key",
      inbox_url: "https://wanderer.example/users/demo/inbox"
    )
  end
  let(:actor_resolver) { instance_double(Federation::ActorResolver) }
  let(:webfinger_resolver) { instance_double(Federation::WebFingerResolver) }

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow(actor_resolver).to receive(:resolve).with(remote.uri).and_return(remote)
    allow(webfinger_resolver).to receive(:resolve).with("@demo@wanderer.example").and_return(remote)
  end

  def service(target)
    described_class.new(user:, target:, actor_resolver:, webfinger_resolver:)
  end

  it "creates one pending Follow and one stable outbox event" do
    following = service(remote.uri).call!

    expect(following).to be_pending
    expect(following.follower_actor.user).to eq(user)
    expect(following.followed_actor).to eq(remote)
    expect(following.uri).to eq(FederationOutboxEvent.find_by!(activity_type: "Follow").activity_uri)
    expect(following.uri).to start_with("#{following.follower_actor.uri}/activities/")
    expect(FederationOutboxEvent.where(activity_type: "Follow").count).to eq(1)
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued
  end

  # docs/dev/FEDERATION.md: a Follow URI derived from the two actors could be
  # computed by anyone and used to probe who follows whom.
  it "gives the first Follow an identity nobody can compute from the two actors" do
    following = service(remote.uri).call!

    expect(following.uri).not_to eq(Federation::Outbox::EventBuilder.activity_uri_for(
      object_uri: following.follower_actor.uri, activity_type: "Follow", idempotency_key: "follow:#{remote.uri}"
    ))
  end

  it "rebuilds a missing Follow intent under the relationship's new identity" do
    following = service(remote.uri).call!
    FederationOutboxEvent.where(activity_type: "Follow").delete_all

    result = service(remote.uri).call!

    expect(result).to eq(following)
    expect(result.reload.uri).to eq(FederationOutboxEvent.find_by!(activity_type: "Follow").activity_uri)
  end

  it "reuses an active relationship and does not create another event" do
    first = service("@demo@wanderer.example").call!
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    second = service(remote.uri).call!

    expect(second).to eq(first)
    expect(Following.count).to eq(1)
    expect(FederationOutboxEvent.count).to eq(1)
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued
  end

  it "creates a new activity identity when following again after an undo" do
    first = service(remote.uri).call!
    Federation::Unfollow.new(user:, target: remote.uri, actor_resolver:, webfinger_resolver:).call!

    second = service(remote.uri).call!

    expect(second).not_to eq(first)
    expect(second).to be_pending
    expect(second.uri).not_to eq(first.uri)
    expect(Following.count).to eq(2)
    expect(Following.active.count).to eq(1)
    expect(FederationOutboxEvent.where(activity_type: "Follow").count).to eq(2)
  end

  it "retries a terminally failed follow with a new activity identity" do
    following = service(remote.uri).call!
    event = FederationOutboxEvent.find_by!(activity_type: "Follow")
    event.mark_failed!(error: "remote refused")
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    result = service(remote.uri).call!

    expect(result).to eq(following)
    expect(result.reload).to be_pending
    expect(result.uri).not_to eq(event.activity_uri)
    expect(FederationOutboxEvent.where(activity_type: "Follow").count).to eq(2)
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued
  end

  it "asks again after a refusal under a new identity the Accept can answer" do
    following = service(remote.uri).call!
    FederationOutboxEvent.find_by!(activity_type: "Follow").mark_complete!
    following.reject!

    result = service(remote.uri).call!

    expect(result).to eq(following)
    expect(result.reload).to be_pending
    expect(FederationOutboxEvent.where(activity_type: "Follow").count).to eq(2)
    expect(result.uri).to eq(FederationOutboxEvent.where(activity_type: "Follow").order(:id).last.activity_uri)
  end

  it "creates a pending local request without any federation event" do
    target_user = create(:user, username: "paul")

    following = service("paul").call!

    expect(following).to be_pending
    expect(following.followed_actor.user).to eq(target_user)
    expect(FederationOutboxEvent.count).to eq(0)
  end

  context "with federation disabled" do
    before { ENV["FEDERATION_ENABLED"] = "false" }

    it "still creates and accepts a local relationship without discovery or delivery" do
      target_user = create(:user, username: "paul")

      following = service("paul").call!
      Federation::FollowDecision.new(following:, decision: "accept").call!

      expect(following.reload).to be_accepted
      expect(following.followed_actor.user).to eq(target_user)
      expect(actor_resolver).not_to have_received(:resolve)
      expect(webfinger_resolver).not_to have_received(:resolve)
      expect(FederationOutboxEvent.count).to eq(0)
      expect(Federation::ExpandOutboxEventJob).not_to have_been_enqueued
    end

    %w[@demo@wanderer.example demo@wanderer.example acct:demo@wanderer.example https://wanderer.example/users/demo].each do |target|
      it "refuses #{target} before resolving or creating anything" do
        expect { service(target).call! }.to raise_error(described_class::InvalidTarget, "federation is disabled")

        expect(actor_resolver).not_to have_received(:resolve)
        expect(webfinger_resolver).not_to have_received(:resolve)
        expect(Following.count).to eq(0)
        expect(FederationOutboxEvent.count).to eq(0)
      end
    end

    it "undoes a local relationship" do
      create(:user, username: "paul")
      following = service("paul").call!

      Federation::Unfollow.new(user:, target: "paul").call!

      expect(Following.active).not_to include(following)
      expect(FederationOutboxEvent.count).to eq(0)
    end

    it "refuses to undo a remote relationship before any request" do
      expect {
        Federation::Unfollow.new(user:, target: remote.uri, actor_resolver:, webfinger_resolver:).call!
      }.to raise_error(Federation::Unfollow::InvalidTarget, "federation is disabled")
      expect(actor_resolver).not_to have_received(:resolve)
    end

    it "refuses to answer a remote follower" do
      local_actor = Federation::ActorProvisioner.new(user:).call!
      following = create(:following, follower_actor: remote, followed_actor: local_actor,
                                     uri: "https://wanderer.example/activities/follow-1")

      expect {
        Federation::FollowDecision.new(following:, decision: "accept").call!
      }.to raise_error(Federation::FollowDecision::InvalidDecision, "federation is disabled")
      expect(following.reload).to be_pending
      expect(FederationOutboxEvent.count).to eq(0)
    end
  end

  it "notifies a local target of the pending request" do
    target_user = create(:user, username: "paul")

    following = service("paul").call!

    notification = Notification.find_by!(user: target_user, kind: "follow_request", subject: following)
    expect(notification.actor).to eq(following.follower_actor)
    expect(notification).not_to be_read
  end

  it "does not create a local notification for a remote follow" do
    service(remote.uri).call!

    expect(Notification.where(kind: "follow_request")).to be_empty
  end

  it "keeps one pending request when a local account is asked twice" do
    target_user = create(:user, username: "paul")
    first = service("paul").call!
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    second = service("paul").call!

    expect(second).to eq(first)
    expect(second.reload).to be_pending
    expect(Following.count).to eq(1)
    expect(Notification.where(user: target_user, kind: "follow_request").count).to eq(1)
  end

  it "resets a rejected local request to pending on a new ask" do
    create(:user, username: "paul")
    following = service("paul").call!
    following.reject!

    result = service("paul").call!

    expect(result).to eq(following)
    expect(result.reload).to be_pending
    expect(Following.count).to eq(1)
  end

  it "can follow a local account again after an undo" do
    create(:user, username: "paul")
    first = service("paul").call!
    Federation::Unfollow.new(user:, target: "paul").call!

    second = service("paul").call!

    expect(second).not_to eq(first)
    expect(second).to be_pending
    expect(Following.count).to eq(2)
    expect(Following.active.count).to eq(1)
  end

  it "rejects self follows" do
    expect { service("marie").call! }.to raise_error(described_class::InvalidTarget)
  end

  it "rejects a blocked actor" do
    create(:federation_actor_block, actor_uri: remote.uri)

    expect { service(remote.uri).call! }.to raise_error(described_class::InvalidTarget, /blocked/)
    expect(Following.count).to eq(0)
  end

  it "rejects a blocked domain" do
    create(:federation_domain_block, domain: "wanderer.example")

    expect { service(remote.uri).call! }.to raise_error(described_class::InvalidTarget, /blocked/)
  end
end

RSpec.describe Federation::Unfollow do
  let(:user) { create(:user, username: "marie") }
  let(:remote) { create(:actor, uri: "https://wanderer.example/users/demo") }
  let(:actor_resolver) { instance_double(Federation::ActorResolver) }
  let(:webfinger_resolver) { instance_double(Federation::WebFingerResolver) }

  before do
    allow(actor_resolver).to receive(:resolve).with(remote.uri).and_return(remote)
  end

  it "marks a remote relationship undone and creates one Undo event" do
    local = Federation::ActorProvisioner.new(user:).call!
    following = create(:following, follower_actor: local, followed_actor: remote, uri: "#{local.uri}/activities/follow-1")

    result = described_class.new(user:, target: remote.uri, actor_resolver:, webfinger_resolver:).call!

    expect(result).to eq(following)
    expect(following.reload).to be_undone
    expect(FederationOutboxEvent.where(activity_type: "Undo").count).to eq(1)
  end

  it "withdraws the viewer's entitlements for the remote author" do
    local = Federation::ActorProvisioner.new(user:).call!
    create(:following, :accepted, follower_actor: local, followed_actor: remote, uri: "#{local.uri}/activities/follow-1")
    note = create(:remote_note, actor: remote)
    recipient = create(:remote_note_recipient, remote_note: note, recipient_actor: local)

    described_class.new(user:, target: remote.uri, actor_resolver:, webfinger_resolver:).call!

    expect(recipient.reload).to be_withdrawn
    expect(recipient.withdrawal_reason).to eq("unfollow")
  end

  it "purges a followers-only note when unfollow withdraws its last entitlement" do
    local = Federation::ActorProvisioner.new(user:).call!
    create(:following, :accepted, follower_actor: local, followed_actor: remote, uri: "#{local.uri}/activities/follow-1")
    note = create(:remote_note, actor: remote, audience: "followers")
    attachment = create(:remote_note_attachment, remote_note: note, status: "cached")
    create(:remote_note_recipient, remote_note: note, recipient_actor: local)

    described_class.new(user:, target: remote.uri, actor_resolver:, webfinger_resolver:).call!

    expect(note.reload).to be_location_data_purged
    expect(attachment.reload).to be_purged
  end

  it "withdraws and purges an entitled remote course" do
    local = Federation::ActorProvisioner.new(user:).call!
    create(:following, :accepted, follower_actor: local, followed_actor: remote, uri: "#{local.uri}/activities/follow-1")
    segment = create(:remote_segment, actor: remote, audience: "followers")
    attachment = create(:remote_segment_attachment, remote_segment: segment, status: "cached")
    recipient = create(:remote_segment_recipient, remote_segment: segment, recipient_actor: local)

    described_class.new(user:, target: remote.uri, actor_resolver:, webfinger_resolver:).call!

    expect(recipient.reload).to be_withdrawn
    expect(recipient.withdrawal_reason).to eq("unfollow")
    expect(attachment.reload).to be_purged
    expect(segment.reload).to be_location_data_purged
  end

  it "retains a public note's media when unfollow withdraws its last entitlement" do
    local = Federation::ActorProvisioner.new(user:).call!
    create(:following, :accepted, follower_actor: local, followed_actor: remote, uri: "#{local.uri}/activities/follow-1")
    note = create(:remote_note, actor: remote)
    attachment = create(:remote_note_attachment, remote_note: note, status: "cached")
    create(:remote_note_recipient, remote_note: note, recipient_actor: local)

    described_class.new(user:, target: remote.uri, actor_resolver:, webfinger_resolver:).call!

    expect(note.reload).not_to be_location_data_purged
    expect(attachment.reload).to be_cached
  end

  it "undoes a local follow without a federation event" do
    target_user = create(:user, username: "paul")
    local = Federation::ActorProvisioner.new(user:).call!
    target_actor = Federation::ActorProvisioner.new(user: target_user).call!
    following = create(:following, :accepted, follower_actor: local, followed_actor: target_actor)

    described_class.new(user:, target: "paul").call!

    expect(following.reload).to be_undone
    expect(FederationOutboxEvent.count).to eq(0)
  end

  it "withdraws the target's pending request notification" do
    target_user = create(:user, username: "paul")
    local = Federation::ActorProvisioner.new(user:).call!
    target_actor = Federation::ActorProvisioner.new(user: target_user).call!
    following = create(:following, follower_actor: local, followed_actor: target_actor)
    notification = create(:notification, user: target_user, actor: local, subject: following)

    described_class.new(user:, target: "paul").call!

    expect(Notification.where(id: notification.id)).not_to exist
  end

  %w[demo@wanderer.example @Demo@wanderer.example acct:demo@wanderer.example].each do |target|
    it "unfollows #{target} from the stored actor without any request" do
      remote.update!(acct: "demo@wanderer.example", handle: "demo@wanderer.example")
      local = Federation::ActorProvisioner.new(user:).call!
      following = create(:following, :accepted, follower_actor: local, followed_actor: remote,
                                                uri: "#{local.uri}/activities/follow-1")

      described_class.new(user:, target:, actor_resolver:, webfinger_resolver:).call!

      expect(following.reload).to be_undone
      expect(actor_resolver).not_to have_received(:resolve)
      expect(FederationOutboxEvent.where(activity_type: "Undo").count).to eq(1)
    end
  end

  it "unfollows an author whose instance deleted it" do
    local = Federation::ActorProvisioner.new(user:).call!
    following = create(:following, :accepted, follower_actor: local, followed_actor: remote,
                                              uri: "#{local.uri}/activities/follow-1")
    remote.tombstone!

    described_class.new(user:, target: remote.uri, actor_resolver:, webfinger_resolver:).call!

    expect(following.reload).to be_undone
    expect(actor_resolver).not_to have_received(:resolve)
  end

  it "raises when no relationship exists" do
    expect { described_class.new(user:, target: remote.uri, actor_resolver:, webfinger_resolver:).call! }
      .to raise_error(described_class::InvalidTarget)
  end
end
