# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Delivery::RecipientAuthorizer do
  let(:owner) { create(:user) }
  let(:owner_actor) { create(:local_actor, user: owner) }
  let(:workout) { create(:workout, user: owner) }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user: owner) }
  let(:publication) { publish_workout!(user: owner, workout:, profile:) }
  let(:create_event) do
    FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri)
  end
  let(:remote) do
    create(:actor, inbox_url: "https://remote.example/inbox", capability_profile: "public_only")
  end

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    create(:following, :accepted, follower_actor: remote, followed_actor: owner_actor)
  end

  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  def authorize(event, actor)
    described_class.new(event:, actor:, client: instance_double(Federation::Transport::Client).as_null_object).call
  end

  def followers_create_event
    publication = create(
      :workout_publication,
      workout: create(:workout, user: owner),
      publishing_profile: create(:publishing_profile, :followers, user: owner)
    )
    Federation::Outbox::EventBuilder.new(
      actor: owner_actor,
      subject_type: "WorkoutPublication",
      subject_id: publication.id,
      workout_publication_id: publication.id,
      activity_type: "Create",
      object_uri: publication.object_uri,
      idempotency_key: "test:followers:#{publication.id}",
      payload: { "type" => "Create" },
      audience: { "to" => [ "#{owner_actor.uri}/followers" ], "cc" => [] }
    ).call!
  end

  it "allows a public Create to an accepted follower" do
    expect(authorize(create_event, remote).allowed?).to be(true)
  end

  it "denies a public Create after unfollow" do
    Following.find_by!(follower_actor: remote, followed_actor: owner_actor).undo!

    expect(authorize(create_event, remote).allowed?).to be(false)
  end

  it "denies a public Create after the recipient is tombstoned" do
    remote.tombstone!

    expect(authorize(create_event, remote).allowed?).to be(false)
  end

  it "denies a blocked recipient" do
    create(:federation_actor_block, actor_uri: remote.uri)

    expect(authorize(create_event, remote).allowed?).to be(false)
  end

  it "denies a recipient on a blocked authority" do
    create(:federation_domain_block, domain: "remote.example")

    expect(authorize(create_event, remote).allowed?).to be(false)
  end

  it "denies a public Create after the publication is deleted" do
    publication.mark_deleted!

    expect(authorize(create_event, remote).allowed?).to be(false)
  end

  it "uses the personal inbox unless shared delivery is explicitly authorized" do
    remote.update!(
      capability_profile: "unknown",
      shared_inbox_url: "https://remote.example/shared"
    )

    expect(authorize(create_event, remote).inbox_url).to eq("https://remote.example/inbox")
  end

  it "uses the shared inbox for an explicitly authorized shared peer on public Creates" do
    remote.update!(
      capability_profile: "restricted_shared_inbox",
      shared_inbox_url: "https://remote.example/shared"
    )

    expect(authorize(create_event, remote).inbox_url).to eq("https://remote.example/shared")
  end

  # The followers audience is publishable for local followers whatever the
  # switch says (docs/dev/FEDERATION.md); this is the gate that keeps it home.
  it "denies followers-only Creates even to promoted peers while restricted federation is off" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
    remote.update!(
      capability_profile: "restricted_shared_inbox",
      shared_inbox_url: "https://remote.example/shared"
    )
    followers_publication = create(
      :workout_publication,
      workout: create(:workout, user: owner),
      publishing_profile: create(:publishing_profile, :followers, user: owner)
    )
    followers_event = Federation::Outbox::EventBuilder.new(
      actor: owner_actor,
      subject_type: "WorkoutPublication",
      subject_id: followers_publication.id,
      workout_publication_id: followers_publication.id,
      activity_type: "Create",
      object_uri: followers_publication.object_uri,
      idempotency_key: "test:followers:#{followers_publication.id}",
      payload: { "type" => "Create" },
      audience: { "to" => [ "#{owner_actor.uri}/followers" ], "cc" => [] }
    ).call!

    result = authorize(followers_event, remote)
    expect(result.allowed?).to be(false)
    expect(result.reason).to eq("audience and capability are incompatible")
  end

  it "allows a followers-only Create to a promoted accepted follower while restricted federation is on" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    remote.update!(capability_profile: "restricted_fetch")

    expect(authorize(followers_create_event, remote).allowed?).to be(true)
  end

  it "denies a followers-only Create to an unpromoted accepted follower while restricted federation is on" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)

    expect(authorize(followers_create_event, remote).allowed?).to be(false)
  end

  it "denies a Delete to a recipient outside the attempted Create set" do
    stranger = create(:actor, inbox_url: "https://remote.example/stranger")
    delete_event = Federation::Outbox::EventBuilder.new(
      actor: owner_actor,
      subject_type: "WorkoutPublication",
      subject_id: publication.id,
      workout_publication_id: publication.id,
      activity_type: "Delete",
      object_uri: publication.object_uri,
      idempotency_key: "test:delete:#{publication.id}",
      payload: { "type" => "Delete" },
      audience: { "to" => [ stranger.uri ], "cc" => [] }
    ).call!

    expect(authorize(delete_event, stranger).allowed?).to be(false)
  end
end
