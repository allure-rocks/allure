# frozen_string_literal: true

require "rails_helper"

# The comments relay as the thread host sends it (docs/dev/COMMENTS.md,
# §8.4, §9): every comment the host takes on its public publication, but its
# owner's own, is announced to the instances that publication went to, after
# the publication itself. The Announce stops with its comment or its
# publication, and the host's Undo follows it where it was attempted.
RSpec.describe "The comments relay" do
  let(:owner) { create(:user) }
  let!(:owner_actor) { create(:local_actor, user: owner) }
  let(:workout) { create(:workout, user: owner) }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user: owner) }
  let(:publication) { publish_workout!(user: owner, workout:, profile:) }
  let(:create_event) { FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri) }
  let(:member) { create(:user) }
  let!(:remote) do
    create(:actor, uri: "https://remote.example/users/one", inbox_url: "https://remote.example/inbox",
                   capability_profile: "public_only")
  end
  let(:client) { instance_double(Federation::Transport::Client) }
  let(:resolver) { instance_double(Federation::ActorResolver) }
  let(:accepted) { Federation::Transport::Client::Response.new(202, {}, "", URI("https://remote.example/inbox")) }

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    create(:following, :accepted, follower_actor: remote, followed_actor: owner_actor)
    allow(client).to receive(:validate_url)
    allow(client).to receive(:post).and_return(accepted)
    allow(resolver).to receive(:resolve) { |uri| Actor.find_by!(uri:) }
    allow_any_instance_of(Workouts::MaplibreRouteImageRenderer).to receive(:call)
      .and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "no browser")
  end

  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  def expand(event) = Federation::Outbox::Expander.new(event:, actor_resolver: resolver, client:).call!

  def deliver(delivery)
    delivery.update!(next_attempt_at: nil) if delivery.retrying?
    Federation::Delivery::Deliver.new(delivery:, client:, now: Time.current).call!
    delivery.reload
  end

  def deliver_all(event) = event.reload.deliveries.map { |delivery| deliver(delivery) }

  def finalize_publication! = Workouts::RenderPublicationRouteImageJob.perform_now(publication)

  def publication_delivered!
    finalize_publication!
    expand(create_event)
    deliver_all(create_event)
  end

  def announce_for(comment)
    FederationOutboxEvent.find_by!(activity_uri: Federation::Outbox::CommentAnnounce.activity_uri_for(comment, owner_actor))
  end

  def member_comment(body = "Belle sortie !")
    comment = Comments::Post.new(user: member, target: workout, body:).call!
    [ comment, announce_for(comment) ]
  end

  def recipients_of(event) = event.reload.deliveries.flat_map { |delivery| delivery.recipients.authorized.pluck(:actor_uri) }

  def inbound(activity)
    item = create(:federation_inbox_item, recipient_actor: owner_actor, activity_uri: activity.fetch("id"),
                                          activity_type: activity.fetch("type"), actor_uri: activity.fetch("actor"),
                                          raw: activity)
    Federation::ProcessInboxItemJob.perform_now(item)
    item.reload
  end

  def remote_comment(in_reply_to: publication.object_uri, id: "https://remote.example/api/v1/comment/c1")
    inbound(federation_comment_activity(in_reply_to:, to: owner_actor.uri, id:, actor: remote.uri))
    Comment.find_by!(uri: id)
  end

  it "waits for the publication's own expansion and reaches only its recipients" do
    publication
    _comment, announce = member_comment

    expect(expand(announce)).to eq([])
    expect(announce.reload).to be_pending

    finalize_publication!
    expect { expand(create_event) }.to have_enqueued_job(Federation::ExpandOutboxEventJob).with(announce)
    late = create(:actor, uri: "https://remote.example/users/late", inbox_url: "https://remote.example/late",
                          capability_profile: "public_only")
    create(:following, :accepted, follower_actor: late, followed_actor: owner_actor)

    expand(announce)
    expect(recipients_of(announce)).to eq([ remote.uri ])
  end

  it "posts only once the publication reached the recipient, with the comment embedded" do
    finalize_publication!
    expand(create_event)
    publication_delivery = create_event.deliveries.first
    comment, announce = member_comment
    expand(announce)
    relay_delivery = announce.deliveries.first

    expect(deliver(relay_delivery)).to be_retrying
    expect(client).not_to have_received(:post)

    expect(deliver(publication_delivery)).to be_delivered
    expect(deliver(relay_delivery)).to be_delivered
    expect(client).to have_received(:post).with(remote.inbox_url, hash_including(body: include("\"Announce\"", comment.uri)))
  end

  it "stops with its comment, before and after expansion, and sends no Undo for what never left" do
    publication_delivered!

    unexpanded, unexpanded_announce = member_comment("Premier")
    Comments::Delete.new(user: member, comment: unexpanded).call!
    expect(expand(unexpanded_announce)).to eq([])
    expect(unexpanded_announce.reload).to be_cancelled

    expanded, expanded_announce = member_comment("Second")
    expand(expanded_announce)
    delivery = expanded_announce.deliveries.first
    Comments::Remove.new(user: owner, comment: expanded).call!

    expect(deliver(delivery)).to be_cancelled
    expect(client).to have_received(:post).once
    expect(FederationOutboxEvent.where(activity_type: "Undo")).to be_empty
  end

  it "stops with its publication" do
    publication_delivered!
    _comment, announce = member_comment
    expand(announce)
    delivery = announce.deliveries.first

    Workouts::PublicationWithdrawal.new(user: owner, workout:).call!

    expect(deliver(delivery)).to be_cancelled
  end

  it "undoes a relay where it was attempted, once the Announce settled" do
    publication_delivered!
    comment, announce = member_comment
    expand(announce)
    relay_delivery = announce.deliveries.first
    allow(client).to receive(:post).and_return(
      Federation::Transport::Client::Response.new(503, {}, "", URI(remote.inbox_url))
    )
    expect(deliver(relay_delivery)).to be_retrying

    Comments::Delete.new(user: member, comment:).call!
    undo = FederationOutboxEvent.find_by!(activity_type: "Undo")
    expand(undo)
    undo_delivery = undo.deliveries.first
    allow(client).to receive(:post).and_return(accepted)

    expect(recipients_of(undo)).to eq([ remote.uri ])
    expect(undo.payload).to include(
      "actor" => owner_actor.uri, "object" => { "type" => "Announce", "id" => announce.activity_uri, "object" => comment.uri }
    )
    expect(announce.reload.payload).to include("redacted" => true)
    expect(deliver(undo_delivery)).to be_retrying
    expect(deliver(relay_delivery)).to be_cancelled
    expect(deliver(undo_delivery)).to be_delivered
  end

  it "never changes the publication's delivery summary or the preflight" do
    publication_delivered!
    comment, announce = member_comment
    expand(announce)
    deliver_all(announce)
    Comments::Delete.new(user: member, comment:).call!
    expand(FederationOutboxEvent.find_by!(activity_type: "Undo"))

    expect(Workouts::DeliverySummary.new(publication:).call.state).to eq(:delivered)
    issues = Workouts::PublicationPreflight.new.call.issues
    expect(issues.map(&:code)).not_to include(:publication_outbox_identity_mismatch, :actor_outbox_identity_mismatch)
  end

  describe "of a remote reader's comment" do
    it "announces the author's object as received and undoes it when the author takes it back" do
      publication_delivered!
      comment = remote_comment
      announce = announce_for(comment)

      expect(announce.payload["object"]).to eq(comment.raw)
      expand(announce)
      expect(deliver_all(announce)).to all(be_delivered)

      inbound({ "id" => "https://remote.example/activities/delete-c1", "type" => "Delete", "actor" => remote.uri,
                "object" => { "id" => comment.uri, "type" => "Tombstone" }, "to" => [ owner_actor.uri ] })

      undo = FederationOutboxEvent.find_by!(activity_type: "Undo")
      expect(undo.audience["recipients"]).to eq([ remote.uri ])
      expect(Federation::ExpandOutboxEventJob).to have_been_enqueued.with(undo)
    end

    it "undoes a blocked author's relays once the block commits, without telling the blocked instance" do
      other = create(:actor, uri: "https://other.example/users/two", inbox_url: "https://other.example/inbox",
                             capability_profile: "public_only")
      create(:following, :accepted, follower_actor: other, followed_actor: owner_actor)
      publication_delivered!
      announce = announce_for(remote_comment)
      expand(announce)
      deliver_all(announce)

      Federation::Safety::Blocking.new.block_actor!(actor_uri: remote.uri)

      undo = FederationOutboxEvent.find_by!(activity_type: "Undo")
      expect(Federation::ExpandOutboxEventJob).to have_been_enqueued.with(undo)
      expand(undo)
      expect(recipients_of(undo)).to eq([ other.uri ])
    end

    it "never relays a followers thread" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      remote.update!(capability_profile: "restricted_fetch")
      PublishingProfile.ensure_built_ins_for!(owner)
      followers = create(:workout_publication, workout: create(:workout, user: owner),
                                               publishing_profile: owner.publishing_profiles.find_by!(built_in_key: "followers"))

      comment = remote_comment(in_reply_to: followers.object_uri)

      expect(comment.audience).to eq("followers")
      expect(FederationOutboxEvent.where(activity_type: "Announce")).to be_empty
    end
  end
end
