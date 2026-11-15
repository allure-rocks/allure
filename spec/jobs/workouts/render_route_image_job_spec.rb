# frozen_string_literal: true

require "rails_helper"
require "vips"

RSpec.describe Workouts::RenderRouteImageJob do
  let(:workout) { create(:workout) }

  # The world image is not committed (docs/dev/VIRTUAL-PLATFORMS.md), so the job's
  # lookup is stubbed; the lookup itself is covered in platforms_spec.
  def virtual_world_basemap
    Allure::Virtual::Basemap.new(
      image: "virtual_worlds/zwift/watopia-f4991742.webp",
      bounds: [ 166.87747, -11.74087, 167.03255, -11.62597 ],
      background: "#0884e2"
    )
  end

  before do
    # Unit under test is the wiring, not the tile host: keep the suite offline.
    allow_any_instance_of(Workouts::RouteBasemapFetcher).to receive(:call).and_return(nil)
    allow_any_instance_of(Workouts::MaplibreRouteImageRenderer).to receive(:call) do
      image = Tempfile.new([ "maplibre-route", ".png" ], binmode: true)
      Vips::Image.black(1_600, 900).pngsave(image.path)
      image
    end
    create(:track_segment, workout:, position: 0)
    create(
      :track_segment,
      workout:,
      position: 1,
      points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.08, "lon" => 6.42 },
        { "t" => 60, "d" => 250.0, "lat" => 45.09, "lon" => 6.43 }
      ]
    )
  end

  it "uses the isolated route-images queue" do
    expect(described_class.queue_name).to eq("route_images")
  end

  it "attaches a generated PNG using the public workout identifier" do
    described_class.perform_now(workout)

    workout.reload
    expect(workout.route_image).to be_attached
    expect(workout.route_image.filename.to_s).to eq("route-#{workout.to_param}.png")
    expect(workout.route_image.content_type).to eq("image/png")
    expect(workout.route_image.download.start_with?("\x89PNG".b)).to be(true)
    image = Vips::Image.new_from_buffer(workout.route_image.download, "")
    expect([ image.width, image.height ]).to eq([ 1_600, 900 ])

    expect(workout.route_image_dark).to be_attached
    expect(workout.route_image_dark.filename.to_s).to eq("route-#{workout.to_param}-dark.png")
  end

  it "stamps the renderer generation on the workout" do
    workout.update_columns(route_image_version: 0)

    described_class.perform_now(workout)

    expect(workout.reload.route_image_version).to eq(Workouts::RouteImage::VERSION)
  end

  it "replaces an existing derived image idempotently" do
    workout.route_image.attach(io: StringIO.new("old"), filename: "old.png", content_type: "image/png")
    old_blob = workout.route_image.blob

    described_class.perform_now(workout)

    expect(workout.reload.route_image.blob).not_to eq(old_blob)
    expect(workout.route_image.filename.to_s).to eq("route-#{workout.to_param}.png")
  end

  it "leaves the workout and original file intact when rendering fails" do
    workout.original_file.attach(io: StringIO.new("gpx"), filename: "track.gpx", content_type: "application/gpx+xml")
    allow(Workouts::MaplibreRouteImageRenderer).to receive(:new).and_raise(ArgumentError, "invalid route")

    expect { described_class.perform_now(workout) }.to raise_error(ArgumentError, "invalid route")
    expect(workout.reload).to be_persisted
    expect(workout.original_file).to be_attached
    expect(workout.route_image).not_to be_attached
  end

  it "schedules a bounded retry for a rendering failure" do
    allow(Workouts::MaplibreRouteImageRenderer).to receive(:new)
      .and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "chromium unavailable")

    expect { described_class.perform_now(workout) }.to have_enqueued_job(described_class)
  end

  it "enqueues fallback mode when the final MapLibre attempt fails" do
    allow(Workouts::MaplibreRouteImageRenderer).to receive(:new)
      .and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "chromium unavailable")
    job = described_class.new(workout)
    exception_key = [ Workouts::MaplibreRouteImageRenderer::RenderingError ].to_s
    job.exception_executions = { exception_key => 4 }

    expect { job.perform_now }
      .to have_enqueued_job(described_class).with(workout, fallback: true)
  end

  it "passes the fetched basemap to the light variant of the fallback pair" do
    basemap = Workouts::RouteBasemapFetcher::Basemap.new("png".b, 14, 8_000, 5_000)
    allow_any_instance_of(Workouts::RouteBasemapFetcher).to receive(:call).and_return(basemap)
    light_renderer = instance_double(Workouts::RouteImageRenderer)
    dark_renderer = instance_double(Workouts::RouteImageRenderer)
    light = Tempfile.new([ "route-light", ".png" ], binmode: true)
    dark = Tempfile.new([ "route-dark", ".png" ], binmode: true)
    allow(light_renderer).to receive(:call).and_return(light)
    allow(dark_renderer).to receive(:call).and_return(dark)
    allow(Workouts::RouteImageRenderer).to receive(:new).and_return(light_renderer)
    expect(Workouts::RouteImageRenderer).to receive(:new)
      .with(hash_including(segments: kind_of(Array), line_colour: Workouts::RouteImageRenderer::TRACK_COLOUR, basemap:))
      .and_return(light_renderer)
    expect(Workouts::RouteImageRenderer).to receive(:new)
      .with(hash_including(segments: kind_of(Array), line_colour: Workouts::RouteImageRenderer::TRACK_COLOUR, theme: "dark"))
      .and_return(dark_renderer)
    expect(Workouts::MaplibreRouteImageRenderer).not_to receive(:new)

    described_class.new.perform(workout, fallback: true)

    workout.reload
    expect(workout.route_image).to be_attached
    expect(workout.route_image_dark).to be_attached
  ensure
    light&.close!
    dark&.close!
  end

  it "falls back to the tile-less image when basemap fetching fails" do
    allow_any_instance_of(Workouts::RouteBasemapFetcher).to receive(:call).and_raise(SocketError, "tile host down")

    described_class.new.perform(workout, fallback: true)

    workout.reload
    expect(workout.route_image).to be_attached
    expect(workout.route_image.download.start_with?("\x89PNG".b)).to be(true)
  end

  it "draws a virtual workout on its world's map image" do
    workout.update_columns(
      sport_id: catalog_sport("cycling_virtual").id,
      start_point: "SRID=4326;POINT(166.95251 -11.63555)",
      bounds: [ -11.63655, 166.95251, -11.63555, 166.95351 ]
    )
    basemap = virtual_world_basemap
    allow(Allure::Virtual::Platforms).to receive(:basemap_at).and_return(basemap)
    expect(Workouts::MaplibreRouteImageRenderer).to receive(:new)
      .with(hash_including(virtual_basemap: basemap)).twice do
        image = Tempfile.new([ "maplibre-route", ".png" ], binmode: true)
        Vips::Image.black(1_600, 900).pngsave(image.path)
        instance_double(Workouts::MaplibreRouteImageRenderer, call: image)
      end

    described_class.perform_now(workout.reload)

    expect(workout.reload.route_image).to be_attached
  end

  it "paints a virtual world's fallback image in the world's colour" do
    workout.update_columns(
      sport_id: catalog_sport("cycling_virtual").id,
      start_point: "SRID=4326;POINT(166.95251 -11.63555)",
      bounds: [ -11.63655, 166.95251, -11.63555, 166.95351 ]
    )
    basemap = virtual_world_basemap
    allow(Allure::Virtual::Platforms).to receive(:basemap_at).and_return(basemap)
    light_renderer = instance_double(Workouts::RouteImageRenderer)
    dark_renderer = instance_double(Workouts::RouteImageRenderer)
    light = Tempfile.new([ "route-light", ".png" ], binmode: true)
    dark = Tempfile.new([ "route-dark", ".png" ], binmode: true)
    allow(light_renderer).to receive(:call).and_return(light)
    allow(dark_renderer).to receive(:call).and_return(dark)
    expect(Workouts::RouteImageRenderer).to receive(:new)
      .with(hash_including(background: basemap.background)).and_return(light_renderer)
    expect(Workouts::RouteImageRenderer).to receive(:new)
      .with(hash_including(background: basemap.dark_background)).and_return(dark_renderer)

    described_class.new.perform(workout.reload, fallback: true)

    expect(workout.reload.route_image).to be_attached
  ensure
    light&.close!
    dark&.close!
  end

  it "purges blobs when attachment fails" do
    images = { route_image: StringIO.new("png"), route_image_dark: StringIO.new("png") }
    allow_any_instance_of(ActiveStorage::Attached::One).to receive(:attach).and_raise("attachment failed")

    expect do
      expect { described_class.new.send(:attach_images, workout, images) }
        .to raise_error(described_class::StorageError, "route image storage failed")
    end.not_to change(ActiveStorage::Blob, :count)
  end
end
