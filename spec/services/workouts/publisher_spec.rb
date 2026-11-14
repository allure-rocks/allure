# frozen_string_literal: true

require "rails_helper"
require "vips"

RSpec.describe Workouts::Publisher do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:, title: "Private title", description: "Private description", notes: "Do not publish") }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user:) }

  def publish(delay: nil)
    described_class.new(user:, workout:, profile:, delay:).call!
  end

  def use_four_point_route
    track_segment.destroy!
    create(:track_segment, workout:, points: [
      { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074 },
      { "t" => 60, "d" => 100.0, "lat" => 45.0715, "lon" => 6.4080 },
      { "t" => 120, "d" => 200.0, "lat" => 45.0722, "lon" => 6.4086 },
      { "t" => 180, "d" => 300.0, "lat" => 45.0728, "lon" => 6.4092 }
    ])
  end

  it "publishes immediately by default and keeps the frozen representation" do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    publication = nil
    expect {
      publication = publish
    }.to change(Actor, :count).by(1)

    expect(publication).to be_active
    expect(publication.scheduled_for).to be_within(1.second).of(Time.current)
    expect(publication.object_uri).to eq(Allure::Federation.config.workout_publication_uri(publication.to_param))
    expect(publication.representation).to include(
      "title" => "Private title",
      "description" => "Private description",
      "sport_slug" => workout.sport.slug
    )
    expect(publication.representation["track"]).to be_present
    expect(publication.representation.to_json).not_to include("Do not publish")
    expect(publication).to be_route_image_pending
    event = FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri)
    expect(event).to be_preparing
    expect(workout.reload.active_publications.first).to eq(publication)
    expect(workout.scheduled_publications.first).to be_nil
    # Delivery waits for the image; the activation job is the fallback.
    expect(Workouts::RenderPublicationRouteImageJob).to have_been_enqueued
    expect(Workouts::ActivateScheduledPublicationJob).to have_been_enqueued
    expect(Federation::ExpandOutboxEventJob).not_to have_been_enqueued
  end

  it "creates a scheduled frozen snapshot with no federation trace" do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    publication = publish(delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day"))

    expect(publication).to be_scheduled
    expect(publication.scheduled_for).to be_within(1.second).of(1.day.from_now)
    expect(publication.published_at).to be_within(1.second).of(publication.scheduled_for)
    expect(FederationOutboxEvent.where(workout_publication_id: publication.id)).to be_empty
    expect(Workouts::RenderPublicationRouteImageJob).to have_been_enqueued
    expect(Workouts::ActivateScheduledPublicationJob).to have_been_enqueued
    expect(Federation::ExpandOutboxEventJob).not_to have_been_enqueued
  end

  it "defaults the delay to the profile policy" do
    profile.update!(publish_delay_seconds: PublishingProfile::PUBLISH_DELAYS.fetch("2_weeks"))

    publication = publish

    expect(publication).to be_scheduled
    expect(publication.scheduled_for).to be_within(1.second).of(2.weeks.from_now)
  end

  it "activates in the request path when the profile chooses immediate" do
    profile.update!(publish_delay_seconds: 0)

    publication = publish

    expect(publication).to be_active
    expect(FederationOutboxEvent.where(activity_type: "Create", object_uri: publication.object_uri)).to exist
  end

  it "accepts a per-publish preset override" do
    publication = publish(delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_month"))

    expect(publication.scheduled_for).to be_within(1.second).of(30.days.from_now)
  end

  it "refuses a delay outside the presets" do
    expect { publish(delay: 3_600) }
      .to raise_error(described_class::PublicationError, /délai|delay/)
    expect(workout.reload.workout_publications).to be_empty
  end

  it "refuses a second publication while one is scheduled" do
    publish(delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day"))

    expect { publish }
      .to raise_error(described_class::PublicationError, /programmée|scheduled/)
  end

  it "publishes the workout-level grade-adjusted pace" do
    workout.update!(grade_adjusted_pace: 187)

    publication = publish

    expect(publication.representation.dig("metrics", "grade_adjusted_pace")).to eq(187)
  end

  it "omits record markers by default" do
    publication = publish

    expect(publication.representation).not_to have_key("record_types")
    expect(publication.representation).not_to have_key("record_distances")
  end

  it "omits the recording device by default" do
    publication = publish

    expect(publication.representation).not_to have_key("device")
  end

  it "publishes the recording device when the profile enables it" do
    workout.update!(source: "Garmin Edge 530")
    profile.update!(settings: profile.settings.merge("device" => true))

    publication = publish

    expect(publication.representation["device"]).to eq("Garmin Edge 530")
  end

  it "bounds the published recording device" do
    workout.update!(source: "x" * 500)
    profile.update!(settings: profile.settings.merge("device" => true))

    publication = publish

    expect(publication.representation["device"].length)
      .to eq(Allure::Federation::Privacy::SanitizedPublicationBuilder::MAX_DEVICE_LENGTH)
  end

  it "omits the commute flag by default" do
    workout.update!(commute: true)
    publication = publish

    expect(publication.representation).not_to have_key("commute")
  end

  it "publishes the commute flag when the profile enables it" do
    workout.update!(commute: true)
    profile.update!(settings: profile.settings.merge("commute" => true))

    publication = publish

    expect(publication.representation["commute"]).to be(true)
  end

  it "never publishes a false commute" do
    profile.update!(settings: profile.settings.merge("commute" => true))

    publication = publish

    expect(publication.representation).not_to have_key("commute")
  end

  it "never publishes the derived workout place" do
    workout.update!(places: [ { "name" => "Cimefroide", "kind" => "town" } ])

    publication = publish

    expect(publication.representation).not_to have_key("places")
    expect(publication.representation.to_json).not_to include("Cimefroide")
  end

  it "publishes the held record markers when the profile enables them" do
    profile.update!(settings: profile.settings.merge("records" => true))

    publication = publish

    expect(publication.representation["record_types"]).to include("FD", "HA", "LD", "MS", "AS")
    expect(publication.representation["record_types"]).not_to include("AP", "BP", "MC")
    expect(publication.representation).not_to have_key("record_distances")
  end

  it "filters published record markers by the enabled metrics" do
    profile.update!(settings: profile.settings.merge("records" => true, "metrics" => [ "distance" ]))

    publication = publish

    expect(publication.representation["record_types"]).to eq([ "FD" ])
  end

  it "publishes held best-effort distances without a metric gate" do
    profile.update!(settings: profile.settings.merge("records" => true))
    create(:best_effort, workout:, distance_key: "km5", distance_meters: 5_000, duration_seconds: 1_500)
    create(:effort_record, user:, sport: workout.sport, workout:, distance_key: "km5",
                           distance_meters: 5_000, duration_seconds: 1_500)

    publication = publish

    expect(publication.representation["record_distances"]).to eq([ "km5" ])
  end

  it "publishes the built-in followers profile while restricted federation is on" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    followers = create(:publishing_profile, :followers, :without_endpoint_masks, user:)

    publication = described_class.new(user:, workout:, profile: followers).call!

    expect(publication.audience).to eq("followers")
    expect(publication.profile_snapshot.fetch("audience")).to eq("followers")
    expect(publication.profile_snapshot.fetch("name")).to eq(followers.name)
  end

  it "rejects a route fully hidden by privacy zones" do
    create(:privacy_zone, user:, latitude: 45.071, longitude: 6.4074, radius_meters: 10_000)

    expect { publish }
      .to raise_error(Workouts::Publisher::PublicationError)
    expect(workout.reload.active_publications.first).to be_nil
    expect(workout.reload.scheduled_publications.first).to be_nil
  end

  it "does not mutate a scheduled publication when the source changes" do
    publication = publish
    workout.update!(title: "Changed source title", description: "Changed source description")

    expect(publication.reload.publication_title).to eq("Private title")
    expect(publication.publication_description).to eq("Private description")
  end

  it "stores GPX only when the selected profile allows it" do
    profile.update!(settings: profile.settings.merge("gpx" => true))

    publication = publish

    expect(publication.gpx).to be_attached
    expect(publication.sanitized_gpx_blob_id).to eq(publication.gpx.blob.id)
    expect(publication.gpx.download).to include("<trkpt")
    expect(publication.gpx.download).not_to include("Do not publish")
  end

  it "keeps the actor gate owner-scoped" do
    other = create(:user)

    expect { described_class.new(user: other, workout:, profile:).call! }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  it "requires a privacy zone for each enabled endpoint mask" do
    use_four_point_route
    profile.update!(settings: PublishingProfile::DEFAULT_SETTINGS.merge("mask_start" => true, "mask_finish" => false))
    create(:privacy_zone, user:, latitude: 45.0710, longitude: 6.4074, radius_meters: 100)

    publication = publish
    coordinates = publication.track.dig("features", 0, "geometry", "coordinates")

    expect(coordinates).not_to include([ 6.4074, 45.071 ])
    expect(coordinates).to include([ 6.4092, 45.0728 ])
  end

  it "keeps an unmasked endpoint that sits inside an active zone" do
    use_four_point_route
    create(:privacy_zone, user:, latitude: 45.0710, longitude: 6.4074, radius_meters: 120)

    publication = publish

    expect(publication.track.dig("features", 0, "geometry", "coordinates")).to eq([
      [ 6.4074, 45.0710 ],
      [ 6.4080, 45.0715 ],
      [ 6.4086, 45.0722 ],
      [ 6.4092, 45.0728 ]
    ])
  end

  it "rejects a masked endpoint when no active zone covers it" do
    use_four_point_route
    profile.update!(settings: PublishingProfile::DEFAULT_SETTINGS.merge("mask_start" => true, "mask_finish" => false))

    expect { publish }
      .to raise_error(Workouts::Publisher::PublicationError, /départ|start/)
    expect(workout.reload.active_publications.first).to be_nil
  end

  it "fails closed for malformed persisted source points" do
    allow(track_segment).to receive(:points).and_return([ { "lat" => 45.0710 } ])
    allow(workout).to receive(:track_segments).and_return([ track_segment ])

    expect { publish }
      .to raise_error(Workouts::Publisher::PublicationError)
    expect(workout.reload.active_publications.first).to be_nil
    expect(workout.reload.scheduled_publications.first).to be_nil
  end

  it "schedules even when the route image renderer is unavailable" do
    profile.update!(settings: profile.settings.merge("gpx" => true, "route_image" => true))
    allow(Workouts::RouteImageRenderer).to receive(:new)
      .and_raise(Workouts::RouteImageRenderer::RenderingError, "renderer unavailable")
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    publication = publish(delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day"))

    expect(publication).to be_scheduled
    expect(publication.route_image).not_to be_attached
    expect(publication.gpx).to be_attached
    expect(Workouts::RenderPublicationRouteImageJob).to have_been_enqueued
  end

  it "rolls back the publication when the media cannot be persisted" do
    allow(Federation::ActorProvisioner).to receive(:new).and_raise(StandardError, "actor unavailable")
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect {
      publish
    }.to raise_error(StandardError, "actor unavailable")
    expect(workout.reload.active_publications.first).to be_nil
    expect(workout.reload.scheduled_publications.first).to be_nil
    expect(WorkoutPublication.where(workout:)).to be_empty
    expect(FederationOutboxEvent.where(subject_type: "WorkoutPublication")).to be_empty
    expect(Workouts::ActivateScheduledPublicationJob).not_to have_been_enqueued
    expect(Federation::ExpandOutboxEventJob).not_to have_been_enqueued
  end
end
