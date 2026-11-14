# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::PublicationReplacement do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:, title: "Original") }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:first_profile) { create(:publishing_profile, :without_endpoint_masks, user:) }
  let(:second_profile) do
    create(:publishing_profile, :custom, :without_endpoint_masks, user:, audience: "public")
  end

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }
  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "withdraws the old publication and activates a new identity immediately by default" do
    first = publish_workout!(user:, workout:, profile: first_profile)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    result = described_class.new(user:, workout:, profile: second_profile).call!

    expect(result.old_publication).to be_deleted
    expect(result.new_publication).to be_active
    expect(result.new_publication.uuid).not_to eq(first.uuid)
    expect(result.new_publication.object_uri).not_to eq(first.object_uri)
    expect(workout.reload.active_publications.first.id).to eq(result.new_publication.id)
    expect(workout.reload.scheduled_publications.first).to be_nil
    expect(result.delete_event).to be_present
    expect(result.delete_event.object_uri).to eq(first.object_uri)
    expect(FederationOutboxEvent.where(activity_type: "Update")).to be_empty
    create_event = FederationOutboxEvent.find_by!(
      activity_type: "Create", object_uri: result.new_publication.object_uri
    )
    expect(create_event).to be_preparing
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued.once
    expect(Workouts::RenderPublicationRouteImageJob).to have_been_enqueued.with(result.new_publication)
    expect(Workouts::ActivateScheduledPublicationJob).to have_been_enqueued.with(result.new_publication)
  end

  it "schedules the replacement when a delay preset is selected" do
    first = publish_workout!(user:, workout:, profile: first_profile)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    result = described_class.new(
      user:, workout:, profile: second_profile,
      delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day")
    ).call!

    expect(result.old_publication).to be_deleted
    expect(result.new_publication).to be_scheduled
    expect(result.new_publication.scheduled_for).to be_within(1.second).of(1.day.from_now)
    expect(workout.reload.active_publications.first).to be_nil
    expect(workout.reload.scheduled_publications.first.id).to eq(result.new_publication.id)
    expect(FederationOutboxEvent.where(workout_publication_id: result.new_publication.id)).to be_empty
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued.once
    expect(Workouts::RenderPublicationRouteImageJob).to have_been_enqueued.with(result.new_publication)
    expect(Workouts::ActivateScheduledPublicationJob).to have_been_enqueued.with(result.new_publication)
  end

  it "replaces a public publication with a new followers identity and snapshot" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    first = publish_workout!(user:, workout:, profile: first_profile)
    followers = create(:publishing_profile, :followers, :without_endpoint_masks, user:)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    result = described_class.new(user:, workout:, profile: followers).call!

    expect(result.new_publication).to be_active
    expect(result.new_publication.audience).to eq("followers")
    expect(result.new_publication.profile_snapshot.fetch("audience")).to eq("followers")
    expect(result.new_publication.uuid).not_to eq(first.uuid)
    expect(result.old_publication.reload).to be_deleted
    expect(first.reload.audience).to eq("public")
  end

  it "schedules without a route image render when the replacement excludes it" do
    profile = create(
      :publishing_profile, :custom, :without_endpoint_masks, user:, audience: "public",
      settings: PublishingProfile::DEFAULT_SETTINGS.merge(
        "route_image" => false, "mask_start" => false, "mask_finish" => false
      )
    )
    publish_workout!(user:, workout:, profile: first_profile)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    result = described_class.new(
      user:, workout:, profile:,
      delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day")
    ).call!

    expect(result.new_publication).to be_scheduled
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued.once
    expect(Workouts::RenderPublicationRouteImageJob).not_to have_been_enqueued
    expect(Workouts::ActivateScheduledPublicationJob).to have_been_enqueued.with(result.new_publication)
  end

  it "accepts a per-publish delay override" do
    publish_workout!(user:, workout:, profile: first_profile)

    result = described_class.new(
      user:, workout:, profile: second_profile,
      delay: PublishingProfile::PUBLISH_DELAYS.fetch("2_weeks")
    ).call!

    expect(result.new_publication.scheduled_for).to be_within(1.second).of(2.weeks.from_now)
  end

  it "leaves the old publication active when candidate preparation fails" do
    first = publish_workout!(user:, workout:, profile: first_profile)
    create(:privacy_zone, user:, latitude: 45.071, longitude: 6.4074, radius_meters: 10_000)

    expect {
      described_class.new(user:, workout:, profile: second_profile).call!
    }.to raise_error(Workouts::Publisher::PublicationError)
    expect(first.reload).to be_active
    expect(workout.reload.active_publications.first.id).to eq(first.id)
    expect(FederationOutboxEvent.where(activity_type: "Delete", object_uri: first.object_uri)).to be_empty
  end

  it "rolls back the old Delete when the replacement cannot be persisted" do
    first = publish_workout!(user:, workout:, profile: first_profile)
    allow_any_instance_of(Workouts::PublicationCandidate)
      .to receive(:attach_to!).and_raise(StandardError, "storage unavailable")

    expect {
      described_class.new(user:, workout:, profile: second_profile).call!
    }.to raise_error(StandardError, "storage unavailable")
    expect(first.reload).to be_active
    expect(workout.reload.active_publications.first.id).to eq(first.id)
    expect(workout.reload.scheduled_publications.first).to be_nil
    expect(FederationOutboxEvent.where(activity_type: "Delete", object_uri: first.object_uri)).to be_empty
  end

  it "rejects a second concurrent publish while one is active" do
    publish_workout!(user:, workout:, profile: first_profile)

    expect {
      Workouts::Publisher.new(user:, workout:, profile: second_profile).call!
    }.to raise_error(Workouts::Publisher::PublicationError)
    expect(workout.reload.active_publications.first.publishing_profile).to eq(first_profile)
  end
end
