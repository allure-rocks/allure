# frozen_string_literal: true

module Workouts
  class RenderRouteImageJob < ApplicationJob
    class StorageError < StandardError; end

    queue_as :route_images
    limits_concurrency key: ->(workout, **) { workout }, duration: 10.minutes

    retry_on MaplibreRouteImageRenderer::RenderingError, wait: :polynomially_longer, attempts: 5 do |job, error|
      Rails.error.report(error, handled: true, context: { component: name, fallback: true })
      perform_later(job.arguments.first, fallback: true)
    end
    retry_on RouteImageRenderer::RenderingError, StorageError, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(workout, fallback: false)
      segments = workout.track_segments.map do |segment|
        segment.geom.points.map { [ it.x, it.y ] }
      end
      basemap = virtual_basemap(workout)
      images = fallback ? render_fallback_pair(segments, basemap) : render_maplibre_pair(segments, basemap)
      attach_images(workout, images)
      AutoPublishJob.nudge(workout)
    ensure
      images&.each_value(&:close!)
    end

    private

    # The world map image a virtual activity is drawn on (docs/dev/VIRTUAL-PLATFORMS.md).
    # The sport decides whether a world may apply at all: Zwift's London sits
    # on London, so geometry alone would claim a real ride there.
    def virtual_basemap(workout)
      return nil unless workout.sport.virtual?

      point = workout.start_point
      return nil unless point

      Allure::Virtual::Platforms.basemap_at(
        longitude: point.x, latitude: point.y, public_root: Rails.public_path
      )
    end

    # Both variants render together, so one generation marker on the workout
    # covers them. A dark failure closes the light tempfile before propagating,
    # and the bounded retry re-enqueues the whole pair in fallback mode.
    def render_maplibre_pair(segments, basemap)
      light = MaplibreRouteImageRenderer.new(
        segments:, line_colour: RouteImageRenderer::TRACK_COLOUR, virtual_basemap: basemap
      ).call
      begin
        dark = MaplibreRouteImageRenderer.new(
          segments:,
          line_colour: RouteImageRenderer::TRACK_COLOUR,
          theme: "dark",
          style_url: Allure::Maps.config.dark_style_url,
          virtual_basemap: basemap
        ).call
      rescue StandardError
        light.close!
        raise
      end
      { route_image: light, route_image_dark: dark }
    end

    # The light variant keeps its raster-then-tile-less chain; the dark variant
    # is tile-less by design, since the raster basemap is a light OSM render
    # (DESIGN.md §15.4). A virtual world's fallback is drawn in the world's own
    # colour, dimmed on the dark surface.
    def render_fallback_pair(segments, basemap)
      light = render_fallback(segments:, line_colour: RouteImageRenderer::TRACK_COLOUR, basemap:)
      begin
        dark = RouteImageRenderer.new(
          segments:,
          line_colour: RouteImageRenderer::TRACK_COLOUR,
          theme: "dark",
          background: basemap&.dark_background,
          attribution: basemap&.attribution
        ).call
      rescue StandardError
        light.close!
        raise
      end
      { route_image: light, route_image_dark: dark }
    end

    def render_fallback(segments:, line_colour:, basemap:)
      raster = fetch_basemap(segments)
      RouteImageRenderer.new(
        segments:,
        line_colour:,
        basemap: raster,
        background: raster ? nil : basemap&.background,
        attribution: raster ? nil : basemap&.attribution
      ).call
    end

    # A missing basemap is not a rendering failure: the tile-less image is the
    # designed fallback (same as the interactive map keeping its track when the
    # style fails to load). Only invalid coordinates propagate.
    def fetch_basemap(segments)
      RouteBasemapFetcher.new(segments:).call
    rescue ArgumentError
      raise
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name })
      nil
    end

    def attach_images(workout, images)
      blobs = images.each_with_object({}) do |(name, image), result|
        result[name] = ActiveStorage::Blob.create_and_upload!(
          io: image,
          filename: filename_for(workout, name),
          content_type: "image/png"
        )
      end

      workout.with_lock do
        blobs.each { |name, blob| workout.public_send(name).attach(blob) }
        # Both variants are now of the current renderer generation; the rebuild
        # sweep uses this marker to re-render only what is missing or stale
        # (docs/dev/DERIVATIONS.md).
        workout.update_columns(route_image_version: Workouts::RouteImage::VERSION)
      end
    rescue StandardError => error
      blobs&.each_value { |blob| purge_unattached_blob(blob) }
      raise StorageError, "route image storage failed", cause: error
    end

    def filename_for(workout, name)
      suffix = name == :route_image_dark ? "-dark" : ""
      "route-#{workout.to_param}#{suffix}.png"
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
