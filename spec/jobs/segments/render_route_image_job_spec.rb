# frozen_string_literal: true

require "rails_helper"
require "vips"

RSpec.describe Segments::RenderRouteImageJob do
  let!(:segment) { create(:segment) }

  before do
    # Unit under test is the wiring, not the tile host: keep the suite offline.
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow_any_instance_of(Workouts::RouteBasemapFetcher).to receive(:call).and_return(nil)
    allow_any_instance_of(Workouts::MaplibreRouteImageRenderer).to receive(:call) do
      image = Tempfile.new([ "maplibre-route", ".png" ], binmode: true)
      Vips::Image.black(1_600, 900).pngsave(image.path)
      image
    end
  end

  it "uses the isolated route-images queue" do
    expect(described_class.queue_name).to eq("route_images")
  end

  it "renders the course geometry smoothed at the medium level in both variants" do
    expect(Workouts::MaplibreRouteImageRenderer).to receive(:new)
      .with(hash_including(smoothing: "medium"))
      .twice
      .and_call_original

    described_class.perform_now(segment)
  end

  it "attaches a generated PNG using the public segment identifier" do
    described_class.perform_now(segment)

    segment.reload
    expect(segment.route_image).to be_attached
    expect(segment.route_image.filename.to_s).to eq("segment-#{segment.to_param}.png")
    expect(segment.route_image.content_type).to eq("image/png")
    expect(segment.route_image.download.start_with?("\x89PNG".b)).to be(true)
    image = Vips::Image.new_from_buffer(segment.route_image.download, "")
    expect([ image.width, image.height ]).to eq([ 1_600, 900 ])

    expect(segment.route_image_dark).to be_attached
    expect(segment.route_image_dark.filename.to_s).to eq("segment-#{segment.to_param}-dark.png")
  end

  it "stamps the renderer generation on the segment" do
    described_class.perform_now(segment)

    expect(segment.reload.route_image_version).to eq(Segments::RouteImage::VERSION)
  end

  it "replaces an existing derived image idempotently" do
    segment.route_image.attach(io: StringIO.new("old"), filename: "old.png", content_type: "image/png")
    old_blob = segment.route_image.blob

    described_class.perform_now(segment)

    expect(segment.reload.route_image.blob).not_to eq(old_blob)
    expect(segment.route_image.filename.to_s).to eq("segment-#{segment.to_param}.png")
  end

  it "leaves the segment intact when rendering fails" do
    allow(Workouts::MaplibreRouteImageRenderer).to receive(:new).and_raise(ArgumentError, "invalid route")

    expect { described_class.perform_now(segment) }.to raise_error(ArgumentError, "invalid route")
    expect(segment.reload).to be_persisted
    expect(segment.route_image).not_to be_attached
  end

  it "schedules a bounded retry for a rendering failure" do
    allow(Workouts::MaplibreRouteImageRenderer).to receive(:new)
      .and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "chromium unavailable")

    expect { described_class.perform_now(segment) }.to have_enqueued_job(described_class)
  end

  it "enqueues fallback mode when the final MapLibre attempt fails" do
    allow(Workouts::MaplibreRouteImageRenderer).to receive(:new)
      .and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "chromium unavailable")
    job = described_class.new(segment)
    exception_key = [ Workouts::MaplibreRouteImageRenderer::RenderingError ].to_s
    job.exception_executions = { exception_key => 4 }

    expect { job.perform_now }
      .to have_enqueued_job(described_class).with(segment, fallback: true)
  end

  it "falls back to the tile-less image when basemap fetching fails" do
    allow_any_instance_of(Workouts::RouteBasemapFetcher).to receive(:call).and_raise(SocketError, "tile host down")

    described_class.new.perform(segment, fallback: true)

    segment.reload
    expect(segment.route_image).to be_attached
    expect(segment.route_image.download.start_with?("\x89PNG".b)).to be(true)
  end

  it "purges blobs when attachment fails" do
    images = { route_image: StringIO.new("png"), route_image_dark: StringIO.new("png") }
    allow_any_instance_of(ActiveStorage::Attached::One).to receive(:attach).and_raise("attachment failed")

    expect do
      expect { described_class.new.send(:attach_images, segment, images) }
        .to raise_error(described_class::StorageError, "route image storage failed")
    end.not_to change(ActiveStorage::Blob, :count)
  end

  it "is enqueued when a segment is created" do
    expect { create(:segment, user: segment.user) }
      .to have_enqueued_job(described_class)
  end
end
