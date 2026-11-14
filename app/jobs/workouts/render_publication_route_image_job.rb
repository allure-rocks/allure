# frozen_string_literal: true

module Workouts
  # Renders the published route image on the dedicated route_images worker,
  # where Chromium is available, so a shared card matches the owner image
  # (MapLibre + OpenFreeMap style). Falls back to the operator raster basemap
  # and then to the tile-less Ruby renderer, exactly like the owner pipeline.
  #
  # Both the light and the dark variant are rendered and attached together; the
  # federation Note advertises them as two Image attachments (DESIGN.md §15.4).
  #
  # The Create intent is created `preparing` at publish time and finalized here
  # once the images are attached, so federation sends the Note with its media.
  class RenderPublicationRouteImageJob < ApplicationJob
    class StorageError < StandardError; end

    queue_as :route_images
    limits_concurrency key: ->(publication, **) { publication }, duration: 10.minutes

    retry_on MaplibreRouteImageRenderer::RenderingError, RouteImageRenderer::RenderingError,
             StorageError, wait: :polynomially_longer, attempts: 5 do |job, error|
      job.finalize_without_image(error:)
    end

    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(publication)
      return unless publication.active? || publication.scheduled?

      # Activation may have happened while a scheduled pre-render was in
      # flight: the images are already attached and only the Create intent needs
      # finalizing.
      if route_images_attached?(publication)
        finalize_delivery(publication) if publication.active?
        return
      end

      segments = sanitized_segments(publication)
      if segments.empty?
        return release_intent(publication, error: ArgumentError.new("publication has no sanitized route"))
      end

      images = render_images(publication, segments)
      attach_images(publication, images)
      # A scheduled publication keeps its images for activation; only an active
      # one has a Create intent to finalize.
      finalize_delivery(publication) if publication.active?
    ensure
      images&.each_value(&:close!)
    end

    # Runs after the bounded retries are exhausted: an image failure must not
    # strand federation. The intent is released without the image and delivery
    # proceeds (the card simply keeps its tile-less state).
    def finalize_without_image(error:)
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_publication_id: publication_id })
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

    # The profile's basemap setting is part of the immutable snapshot: with it
    # off the images are drawn without a background, never as a failure
    # fallback. The dark variant is tile-less by design (the raster basemap is a
    # light OSM render); the light variant keeps MapLibre -> raster -> tile-less.
    # A virtual world's image replaces the tile basemap in both variants.
    def render_images(publication, segments)
      basemap = virtual_basemap(publication, segments)
      light = render_light(publication, segments, basemap)
      begin
        dark = render_dark(publication, segments, basemap)
      rescue StandardError
        light.close!
        raise
      end
      { route_image: light, route_image_dark: dark }
    end

    # The world is read from the frozen snapshot, never from the live workout:
    # a publication keeps the map it was published on. The sport must be
    # virtual, because Zwift's London sits on London.
    def virtual_basemap(publication, segments)
      return nil unless publication.basemap_enabled?

      sport = Sport.find_by(slug: publication.representation["sport_slug"])
      return nil unless sport&.virtual?

      point = segments.first&.first
      return nil unless point

      Allure::Virtual::Platforms.basemap_at(
        longitude: point[0], latitude: point[1], public_root: Rails.public_path
      )
    end

    def render_light(publication, segments, basemap)
      return render_tileless(segments, basemap) unless publication.basemap_enabled?

      MaplibreRouteImageRenderer.new(
        segments:, line_colour: RouteImageRenderer::TRACK_COLOUR, virtual_basemap: basemap
      ).call
    rescue MaplibreRouteImageRenderer::RenderingError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, fallback: "raster" })
      render_raster(segments, basemap)
    end

    def render_raster(segments, basemap)
      raster = RouteBasemapFetcher.new(segments:).call
      RouteImageRenderer.new(
        segments:,
        line_colour: RouteImageRenderer::TRACK_COLOUR,
        basemap: raster,
        background: raster ? nil : basemap&.background,
        attribution: raster ? nil : basemap&.attribution
      ).call
    rescue RouteImageRenderer::RenderingError
      render_tileless(segments, basemap)
    end

    def render_tileless(segments, basemap)
      RouteImageRenderer.new(
        segments:,
        line_colour: RouteImageRenderer::TRACK_COLOUR,
        background: basemap&.background,
        attribution: basemap&.attribution
      ).call
    end

    def render_dark(publication, segments, basemap)
      unless publication.basemap_enabled?
        return RouteImageRenderer.new(
          segments:,
          line_colour: RouteImageRenderer::TRACK_COLOUR,
          theme: "dark",
          background: basemap&.dark_background,
          attribution: basemap&.attribution
        ).call
      end

      MaplibreRouteImageRenderer.new(
        segments:,
        line_colour: RouteImageRenderer::TRACK_COLOUR,
        theme: "dark",
        style_url: Allure::Maps.config.dark_style_url,
        virtual_basemap: basemap
      ).call
    rescue MaplibreRouteImageRenderer::RenderingError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, fallback: "tile-less-dark" })
      RouteImageRenderer.new(
        segments:,
        line_colour: RouteImageRenderer::TRACK_COLOUR,
        theme: "dark",
        background: basemap&.dark_background,
        attribution: basemap&.attribution
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
      "route-#{publication.to_param}#{suffix}.png"
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

      event = Federation::Outbox::PublicationCreate.new(publication:).finalize!(event)
      enqueue_expansion(event)
    end

    def release_intent(publication, error: nil)
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_publication_id: publication&.id }) if error
      event = create_event_for(publication)
      return unless event&.preparing?

      event.mark_pending!
      enqueue_expansion(event)
    end

    # The publication's own Create, never an owner's comment riding on it
    # (PLAN_COMMENTS.md §9).
    def create_event_for(publication)
      Workouts::PublicationWithdrawal.find_create_event(publication)
    end

    def enqueue_expansion(event)
      return unless Allure::Federation::Config.enabled? && event&.pending?

      Federation::ExpandOutboxEventJob.perform_later(event)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, outbox_event_id: event&.id })
    end
  end
end
