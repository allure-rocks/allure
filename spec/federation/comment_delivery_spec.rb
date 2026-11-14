# frozen_string_literal: true

require "rails_helper"

# Secondary publication events (PLAN_COMMENTS.md §9): the owner's comment
# rides on its publication without being it. It reaches only the instances
# the publication went to, after the publication itself; it stops with its
# comment or its publication; and it never changes what the owner and the
# operator read about the publication's own delivery.
RSpec.describe "Secondary publication events" do
  let(:owner) { create(:user) }
  let!(:owner_actor) { create(:local_actor, user: owner) }
  let(:workout) { create(:workout, user: owner) }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user: owner) }
  let(:publication) { publish_workout!(user: owner, workout:, profile:) }
  let(:create_event) { FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri) }
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

  def finalize_publication! = Workouts::RenderPublicationRouteImageJob.perform_now(publication)

  def owner_comment(body = "Merci à tous")
    comment = Comments::Post.new(user: owner, target: workout, body:).call!
    [ comment, FederationOutboxEvent.find_by!(activity_uri: comment.activity_uri) ]
  end

  def recipients_of(event) = event.reload.deliveries.flat_map { |delivery| delivery.recipients.authorized.pluck(:actor_uri) }

  it "waits for the publication's own expansion, which enqueues it again" do
    publication
    _comment, event = owner_comment

    expect(expand(event)).to eq([])
    expect(event.reload).to be_pending

    finalize_publication!
    expect { expand(create_event) }.to have_enqueued_job(Federation::ExpandOutboxEventJob).with(event)

    expand(event)
    expect(recipients_of(event)).to eq([ remote.uri ])
  end

  it "reaches only the instances the publication went to" do
    finalize_publication!
    expand(create_event)
    late = create(:actor, uri: "https://remote.example/users/late", inbox_url: "https://remote.example/late",
                          capability_profile: "public_only")
    create(:following, :accepted, follower_actor: late, followed_actor: owner_actor)

    _comment, event = owner_comment
    expand(event)

    expect(recipients_of(event)).to eq([ remote.uri ])
  end

  it "posts only once the publication reached the recipient" do
    finalize_publication!
    expand(create_event)
    publication_delivery = create_event.deliveries.first
    _comment, event = owner_comment
    expand(event)
    comment_delivery = event.deliveries.first

    expect(deliver(comment_delivery)).to be_retrying
    expect(client).not_to have_received(:post)

    expect(deliver(publication_delivery)).to be_delivered
    expect(deliver(comment_delivery)).to be_delivered
    expect(client).to have_received(:post).twice
  end

  it "stops with its comment, before and after expansion" do
    finalize_publication!
    expand(create_event)
    deliver(create_event.deliveries.first)

    unexpanded, unexpanded_event = owner_comment("Premier")
    Comments::Delete.new(user: owner, comment: unexpanded).call!
    expect(expand(unexpanded_event)).to eq([])
    expect(unexpanded_event.reload).to be_cancelled

    expanded, expanded_event = owner_comment("Second")
    expand(expanded_event)
    delivery = expanded_event.deliveries.first
    Comment.where(id: expanded.id).update_all(status: "removed", removal_reason: "owner", removed_at: Time.current)

    expect(deliver(delivery)).to be_cancelled
    expect(client).to have_received(:post).once
  end

  it "stops with its publication" do
    finalize_publication!
    expand(create_event)
    deliver(create_event.deliveries.first)
    _comment, event = owner_comment
    expand(event)
    delivery = event.deliveries.first

    Workouts::PublicationWithdrawal.new(user: owner, workout:).call!

    expect(deliver(delivery)).to be_cancelled
    expect(client).to have_received(:post).once
  end

  it "follows the comment's own Create with its Delete" do
    finalize_publication!
    expand(create_event)
    deliver(create_event.deliveries.first)
    comment, event = owner_comment
    expand(event)
    deliver(event.deliveries.first)

    Comments::Delete.new(user: owner, comment:).call!
    delete_event = FederationOutboxEvent.find_by!(activity_type: "Delete", object_uri: comment.uri)
    expand(delete_event)

    expect(delete_event.subject_type).to eq("WorkoutPublication")
    expect(recipients_of(delete_event)).to eq([ remote.uri ])
    expect(deliver(delete_event.deliveries.first)).to be_delivered
  end

  it "never changes the publication's delivery summary, its rollup, or the preflight" do
    finalize_publication!
    expand(create_event)
    deliver(create_event.deliveries.first)
    _comment, event = owner_comment
    expand(event)
    event.deliveries.first.update!(status: "failed", last_error: "remote HTTP 500")

    summary = Workouts::DeliverySummary.new(publication:).call
    expect(summary.state).to eq(:delivered)
    expect(summary.failed_deliveries).to eq(0)

    rollup = Admin::Publications::DeliveryRollup.new(kind: "workouts", publication_ids: [ publication.id ]).call
    expect(rollup.fetch(publication.id)).to eq(delivered: 1, open: 0, failed: 0)

    issues = Workouts::PublicationPreflight.new.call.issues
    expect(issues.map(&:code)).not_to include(:publication_outbox_identity_mismatch, :actor_outbox_identity_mismatch)
  end

  it "still flags a publication event that names a foreign object" do
    finalize_publication!
    Federation::Outbox::EventBuilder.new(
      actor: owner_actor, subject_type: "WorkoutPublication", subject_id: publication.id,
      workout_publication_id: publication.id, activity_type: "Create",
      object_uri: "#{Allure::Federation.config.base_url}/api/v1/trail/other", idempotency_key: "stray",
      payload: { "type" => "Create" }, audience: { "to" => [], "cc" => [] }
    ).call!

    issues = Workouts::PublicationPreflight.new.call.issues
    expect(issues.map(&:code)).to include(:publication_outbox_identity_mismatch)
  end
end
