# frozen_string_literal: true

module Segments
  # Renders the owner image for a segment, route or loop on the dedicated
  # route_images worker, with the same MapLibre -> raster -> tile-less fallback
  # chain as workout images (docs/dev/DERIVATIONS.md). Course images are always
  # smoothed at the medium level (docs/dev/MAPS.md): a course is a reusable
  # corridor, not a recording, and the live segment map reads the same display
  # geometry. The image is derived from the segment's own geometry, never from
  # the source workout's track, and is served only through its application
  # endpoint.
  #
  # Both variants (light and dark, DESIGN.md §15.4) are rendered together and
  # carry the single segment generation marker.
  class RenderRouteImageJob < ApplicationJob
    class StorageError < StandardError; end

    SMOOTHING = "medium"

    queue_as :route_images
    limits_concurrency key: ->(segment, **) { segment }, duration: 10.minutes

    retry_on Workouts::MaplibreRouteImageRenderer::RenderingError, wait: :polynomially_longer, attempts: 5 do |job, error|
      Rails.error.report(error, handled: true, context: { component: name, fallback: true })
      perform_later(job.arguments.first, fallback: true)
    end
    retry_on Workouts::RouteImageRenderer::RenderingError, StorageError, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(segment, fallback: false)
      segments = [ segment.geom.points.map { [ it.x, it.y ] } ]
      images = fallback ? render_fallback_pair(segments) : render_maplibre_pair(segments)
      attach_images(segment, images)
    ensure
      images&.each_value(&:close!)
    end

    private

    def render_maplibre_pair(segments)
      light = Workouts::MaplibreRouteImageRenderer.new(
        segments:,
        line_colour: Workouts::RouteImageRenderer::TRACK_COLOUR,
        smoothing: SMOOTHING
      ).call
      begin
        dark = Workouts::MaplibreRouteImageRenderer.new(
          segments:,
          line_colour: Workouts::RouteImageRenderer::TRACK_COLOUR,
          smoothing: SMOOTHING,
          theme: "dark",
          style_url: Allure::Maps.config.dark_style_url
        ).call
      rescue StandardError
        light.close!
        raise
      end
      { route_image: light, route_image_dark: dark }
    end

    # The light variant keeps its raster-then-tile-less chain; the dark variant
    # is tile-less by design, since the raster basemap is a light OSM render
    # (DESIGN.md §15.4).
    def render_fallback_pair(segments)
      light = render_fallback(segments)
      begin
        dark = Workouts::RouteImageRenderer.new(
          segments:,
          line_colour: Workouts::RouteImageRenderer::TRACK_COLOUR,
          smoothing: SMOOTHING,
          theme: "dark"
        ).call
      rescue StandardError
        light.close!
        raise
      end
      { route_image: light, route_image_dark: dark }
    end

    def render_fallback(segments)
      basemap = fetch_basemap(segments)
      Workouts::RouteImageRenderer.new(
        segments:,
        line_colour: Workouts::RouteImageRenderer::TRACK_COLOUR,
        basemap:,
        smoothing: SMOOTHING
      ).call
    end

    # A missing basemap is not a rendering failure: the tile-less image is the
    # designed fallback. Only invalid coordinates propagate.
    def fetch_basemap(segments)
      Workouts::RouteBasemapFetcher.new(segments:).call
    rescue ArgumentError
      raise
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name })
      nil
    end

    def attach_images(segment, images)
      blobs = images.each_with_object({}) do |(name, image), result|
        result[name] = ActiveStorage::Blob.create_and_upload!(
          io: image,
          filename: filename_for(segment, name),
          content_type: "image/png"
        )
      end

      segment.with_lock do
        blobs.each { |name, blob| segment.public_send(name).attach(blob) }
        # Both variants are now of the current renderer generation; the rebuild
        # sweeps use this marker to re-render only what is stale
        # (docs/dev/DERIVATIONS.md).
        segment.update_columns(route_image_version: Segments::RouteImage::VERSION)
      end
    rescue StandardError => error
      blobs&.each_value { |blob| purge_unattached_blob(blob) }
      raise StorageError, "route image storage failed", cause: error
    end

    def filename_for(segment, name)
      suffix = name == :route_image_dark ? "-dark" : ""
      "segment-#{segment.to_param}#{suffix}.png"
    end

    def purge_unattached_blob(blob)
      return unless blob&.persisted?
      return if blob.attachments.exists?

      blob.purge
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name })
    end
  end
end
