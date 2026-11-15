# frozen_string_literal: true

require "rails_helper"
require "vips"

RSpec.describe Workouts::RenderPublicationRouteImageJob do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user:) }

  # The world image is not committed (docs/dev/VIRTUAL-PLATFORMS.md), so the job's
  # lookup is stubbed; the lookup itself is covered in platforms_spec.
  def virtual_world_basemap
    Allure::Virtual::Basemap.new(
      image: "virtual_worlds/zwift/watopia-f4991742.webp",
      bounds: [ 166.87747, -11.74087, 167.03255, -11.62597 ],
      background: "#0884e2"
    )
  end

  def publish
    publish_workout!(user:, workout:, profile:)
  end

  def png_tempfile
    Tempfile.new([ "publication-route", ".png" ], binmode: true).tap do |file|
      file.write(Vips::Image.black(256, 256).write_to_buffer(".png").b)
      file.rewind
    end
  end

  def create_event(publication)
    FederationOutboxEvent.find_by!(
      workout_publication_id: publication.id,
      subject_type: "WorkoutPublication",
      activity_type: "Create"
    )
  end

  # Each renderer call gets its own tempfile: the light and dark variants are
  # rendered by two separate calls, and an IO cannot be uploaded twice.
  def stub_maplibre_renderer
    allow(Workouts::MaplibreRouteImageRenderer).to receive(:new) do
      instance_double(Workouts::MaplibreRouteImageRenderer, call: png_tempfile)
    end
  end

  it "renders with MapLibre, attaches both images and finalizes delivery" do
    publication = publish
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    stub_maplibre_renderer

    described_class.perform_now(publication)

    publication.reload
    expect(publication.route_image).to be_attached
    expect(publication.route_image_dark).to be_attached
    expect(publication.sanitized_route_image_blob_id).to eq(publication.route_image.blob.id)
    expect(publication.sanitized_route_image_dark_blob_id).to eq(publication.route_image_dark.blob.id)
    event = create_event(publication)
    expect(event).to be_pending
    expect(event.payload.dig("object", "attachment")).to include(
      include("type" => "Image", "mediaType" => "image/png")
    )
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued
  end

  it "falls back to the raster basemap when MapLibre fails" do
    publication = publish
    basemap = Workouts::RouteBasemapFetcher::Basemap.new(
      Vips::Image.black(256, 256).write_to_buffer(".png").b, 12, 0, 0
    )
    allow_any_instance_of(Workouts::RouteBasemapFetcher).to receive(:call).and_return(basemap)
    allow_any_instance_of(Workouts::MaplibreRouteImageRenderer)
      .to receive(:call).and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "browser unavailable")
    allow(Workouts::RouteImageRenderer).to receive(:new).and_call_original
    expect(Workouts::RouteImageRenderer).to receive(:new)
      .with(hash_including(basemap:))
      .and_call_original

    described_class.perform_now(publication)

    expect(publication.reload.route_image).to be_attached
    expect(publication.route_image_dark).to be_attached
    expect(create_event(publication)).to be_pending
  end

  it "falls back to the tile-less renderer when no basemap is available" do
    publication = publish
    allow_any_instance_of(Workouts::MaplibreRouteImageRenderer)
      .to receive(:call).and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "browser unavailable")

    described_class.perform_now(publication)

    expect(publication.reload.route_image).to be_attached
    expect(publication.route_image.download.start_with?("\x89PNG".b)).to be(true)
  end

  it "renders without a basemap when the profile disables it" do
    profile.update!(settings: profile.settings.merge("basemap" => false))
    publication = publish
    expect(Workouts::MaplibreRouteImageRenderer).not_to receive(:new)
    expect_any_instance_of(Workouts::RouteBasemapFetcher).not_to receive(:call)

    described_class.perform_now(publication)

    expect(publication.reload.route_image).to be_attached
    expect(publication.route_image.download.start_with?("\x89PNG".b)).to be(true)
    expect(create_event(publication)).to be_pending
  end

  it "draws a virtual publication on its world's map image" do
    workout.update_columns(
      sport_id: catalog_sport("cycling_virtual").id,
      start_point: "SRID=4326;POINT(166.95251 -11.63555)",
      bounds: [ -11.63655, 166.95251, -11.63555, 166.95351 ]
    )
    track_segment.update_columns(
      points: [
        { "t" => 0, "d" => 0.0, "lat" => -11.63555, "lon" => 166.95251, "ele" => 0.0 },
        { "t" => 60, "d" => 250.0, "lat" => -11.63655, "lon" => 166.95351, "ele" => 5.0 }
      ],
      geom: "SRID=4326;LINESTRING(166.95251 -11.63555, 166.95351 -11.63655)"
    )
    workout.association(:track_segments).reset
    publication = publish
    basemap = virtual_world_basemap
    allow(Allure::Virtual::Platforms).to receive(:basemap_at).and_return(basemap)

    calls = 0
    allow(Workouts::MaplibreRouteImageRenderer).to receive(:new) do |**options|
      expect(options[:virtual_basemap]).to eq(basemap)
      calls += 1
      instance_double(Workouts::MaplibreRouteImageRenderer, call: png_tempfile)
    end

    described_class.perform_now(publication)

    expect(calls).to eq(2)
    expect(publication.reload.route_image).to be_attached
  end

  it "never replaces an image that is already attached" do
    publication = publish
    allow_any_instance_of(Workouts::MaplibreRouteImageRenderer)
      .to receive(:call).and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "browser unavailable")
    described_class.perform_now(publication)
    existing_blob_id = publication.reload.sanitized_route_image_blob_id

    expect(Workouts::MaplibreRouteImageRenderer).not_to receive(:new)
    described_class.perform_now(publication)

    expect(publication.reload.sanitized_route_image_blob_id).to eq(existing_blob_id)
  end

  it "releases a preparing intent when rendering permanently fails" do
    publication = publish
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.new(publication).finalize_without_image(error: StandardError.new("boom"))

    expect(create_event(publication)).to be_pending
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued
  end

  it "attaches the image during the delay without touching the outbox" do
    publication = Workouts::Publisher.new(
      user:, workout:, profile:, delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day")
    ).call!
    stub_maplibre_renderer

    described_class.perform_now(publication)

    expect(publication.reload.route_image).to be_attached
    expect(publication.route_image_dark).to be_attached
    expect(FederationOutboxEvent.where(workout_publication_id: publication.id)).to be_empty
  end

  it "finalizes a pending intent when activation raced a pre-render" do
    publication = Workouts::Publisher.new(
      user:, workout:, profile:, delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day")
    ).call!
    stub_maplibre_renderer
    described_class.perform_now(publication)
    # Activation after the pre-render finds the image attached and creates a
    # pending intent; the re-enqueued job must finalize it.
    Workouts::ScheduledPublicationActivation.new(publication:, force: true).call!
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.perform_now(publication)

    expect(create_event(publication)).to be_pending
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued
  end
end
