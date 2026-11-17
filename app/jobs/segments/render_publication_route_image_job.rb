# frozen_string_literal: true

module Segments
  # Renders the published course image on the dedicated route_images worker,
  # where Chromium is available, with the same MapLibre -> raster -> tile-less
  # fallback chain as the owner pipeline. Both the light and the dark variant
  # are rendered and attached together; the federation Note advertises them as
  # two Image attachments (DESIGN.md §15.4). The Create intent is created
  # `preparing` at publish time and finalized here once the images are attached.
  class RenderPublicationRouteImageJob < ApplicationJob
    class StorageError < StandardError; end

    # Course images are always smoothed at the medium level (docs/dev/MAPS.md):
    # a course is a reusable corridor, not a recording, and the display
    # transform happens after sanitization, on the immutable representation.
    # Workout images stay unsmoothed.
    SMOOTHING = "medium"

    queue_as :route_images
    limits_concurrency key: ->(publication, **) { publication }, duration: 10.minutes

    retry_on Workouts::MaplibreRouteImageRenderer::RenderingError, Workouts::RouteImageRenderer::RenderingError,
             StorageError, wait: :polynomially_longer, attempts: 5 do |job, error|
      job.finalize_without_image(error:)
    end

    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(publication)
      return unless publication.active?

      if route_images_attached?(publication)
        finalize_delivery(publication)
        return
      end

      segments = sanitized_segments(publication)
      if segments.empty?
        return release_intent(publication, error: ArgumentError.new("publication has no sanitized course"))
      end

      images = render_images(segments)
      attach_images(publication, images)
      finalize_delivery(publication)
    ensure
      images&.each_value(&:close!)
    end

    # Runs after the bounded retries are exhausted: an image failure must not
    # strand federation. The intent is released without the image and delivery
    # proceeds.
    def finalize_without_image(error:)
      Rails.error.report(error, handled: true, context: {
        component: self.class.name, segment_publication_id: publication_id
      })
      release_intent(arguments.first)
    end

    private

    def publication_id = arguments.first&.id

    def route_images_attached?(publication)
      publication.sanitized_route_image_blob_id.present? &&
        publication.sanitized_route_image_dark_blob_id.present?
    end

    def sanitized_segments(publication)
      Array(publication.representation.dig("track", "features")).filter_map do |feature|
        coordinates = feature.dig("geometry", "coordinates")
        next unless coordinates.is_a?(Array) && coordinates.length >= 2

        coordinates.map do |point|
          [ Float(point[0]), Float(point[1]) ]
        end
      end
    end

    # The light variant keeps MapLibre -> raster -> tile-less; the dark variant
    # is tile-less by design (the raster basemap is a light OSM render).
    def render_images(segments)
      light = render_light(segments)
      begin
        dark = render_dark(segments)
      rescue StandardError
        light.close!
        raise
      end
      { route_image: light, route_image_dark: dark }
    end

    def render_light(segments)
      Workouts::MaplibreRouteImageRenderer.new(
        segments:, line_colour: Workouts::RouteImageRenderer::TRACK_COLOUR, smoothing: SMOOTHING
      ).call
    rescue Workouts::MaplibreRouteImageRenderer::RenderingError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, fallback: "raster" })
      render_raster(segments)
    end

    def render_raster(segments)
      basemap = Workouts::RouteBasemapFetcher.new(segments:).call
      Workouts::RouteImageRenderer.new(
        segments:, line_colour: Workouts::RouteImageRenderer::TRACK_COLOUR, basemap:, smoothing: SMOOTHING
      ).call
    rescue Workouts::RouteImageRenderer::RenderingError
      Workouts::RouteImageRenderer.new(
        segments:, line_colour: Workouts::RouteImageRenderer::TRACK_COLOUR, smoothing: SMOOTHING
      ).call
    end

    def render_dark(segments)
      Workouts::MaplibreRouteImageRenderer.new(
        segments:,
        line_colour: Workouts::RouteImageRenderer::TRACK_COLOUR,
        smoothing: SMOOTHING,
        theme: "dark",
        style_url: Allure::Maps.config.dark_style_url
      ).call
    rescue Workouts::MaplibreRouteImageRenderer::RenderingError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, fallback: "tile-less-dark" })
      Workouts::RouteImageRenderer.new(
        segments:, line_colour: Workouts::RouteImageRenderer::TRACK_COLOUR, smoothing: SMOOTHING, theme: "dark"
      ).call
    end

    def attach_images(publication, images)
      blobs = images.each_with_object({}) do |(name, image), result|
        result[name] = ActiveStorage::Blob.create_and_upload!(
          io: image,
          filename: filename_for(publication, name),
          content_type: "image/png"
        )
      end

      publication.attach_sanitized_route_image!(blobs[:route_image])
      publication.attach_sanitized_route_image_dark!(blobs[:route_image_dark])
    rescue StandardError => error
      blobs&.each_value { |blob| purge_unattached_blob(blob) }
      raise StorageError, "publication route image storage failed", cause: error
    end

    def filename_for(publication, name)
      suffix = name == :route_image_dark ? "-dark" : ""
      "segment-#{publication.to_param}#{suffix}.png"
    end

    def purge_unattached_blob(blob)
      return unless blob&.persisted?
      return if blob.attachments.exists?

      blob.purge
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name })
    end

    def finalize_delivery(publication)
      event = create_event_for(publication)
      return unless event

      event = Federation::Outbox::SegmentCreate.new(publication:).finalize!(event)
      enqueue_expansion(event)
    end

    def release_intent(publication, error: nil)
      if error
        Rails.error.report(error, handled: true, context: {
          component: self.class.name, segment_publication_id: publication&.id
        })
      end
      event = create_event_for(publication)
      return unless event&.preparing?

      event.mark_pending!
      enqueue_expansion(event)
    end

    def create_event_for(publication)
      FederationOutboxEvent.find_by(
        segment_publication_id: publication.id,
        subject_type: "SegmentPublication",
        activity_type: "Create"
      )
    end

    def enqueue_expansion(event)
      return unless Allure::Federation::Config.enabled? && event&.pending?

      Federation::ExpandOutboxEventJob.perform_later(event)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, outbox_event_id: event&.id })
    end
  end
end
