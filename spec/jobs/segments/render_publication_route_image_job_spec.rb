# frozen_string_literal: true

require "rails_helper"
require "vips"

RSpec.describe Segments::RenderPublicationRouteImageJob do
  let(:user) { create(:user) }
  let(:segment) { create(:segment, user:, visibility: "public") }
  let(:publication) { Segments::Publisher.new(user:, segment:).call! }

  def png_tempfile
    Tempfile.new([ "publication-route", ".png" ], binmode: true).tap do |file|
      file.write(Vips::Image.black(256, 256).write_to_buffer(".png").b)
      file.rewind
    end
  end

  def create_event(publication)
    FederationOutboxEvent.find_by!(
      segment_publication_id: publication.id,
      subject_type: "SegmentPublication",
      activity_type: "Create"
    )
  end

  it "renders with MapLibre, attaches both images, and finalizes delivery" do
    publication
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow(Workouts::MaplibreRouteImageRenderer).to receive(:new) do
      instance_double(Workouts::MaplibreRouteImageRenderer, call: png_tempfile)
    end

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

  it "smooths the course image at the medium level" do
    publication
    allow(Workouts::MaplibreRouteImageRenderer)
      .to receive(:new).with(hash_including(smoothing: "medium")) do
        instance_double(Workouts::MaplibreRouteImageRenderer, call: png_tempfile)
      end

    described_class.perform_now(publication)

    expect(publication.reload.route_image).to be_attached
  end

  it "falls back to the tile-less renderer when MapLibre fails" do
    publication
    allow_any_instance_of(Workouts::MaplibreRouteImageRenderer)
      .to receive(:call).and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "browser unavailable")
    allow_any_instance_of(Workouts::RouteBasemapFetcher).to receive(:call).and_return(nil)
    allow_any_instance_of(Workouts::RouteImageRenderer).to receive(:call) { png_tempfile }

    described_class.perform_now(publication)

    expect(publication.reload.route_image).to be_attached
    expect(publication.route_image_dark).to be_attached
    expect(create_event(publication)).to be_pending
  end
end
