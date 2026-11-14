# frozen_string_literal: true

require "digest"
require "json"
require "stringio"

module Workouts
  class PublicationCandidate
    class PreparationError < StandardError
      # A stable code for programs (PLAN_API.md §6.4); the message stays the
      # translated sentence the web shows.
      attr_reader :code

      def initialize(message = nil, code: nil)
        super(message)
        @code = code
      end
    end

    INTEGER_METRICS = %w[
      duration moving_time pause_time average_pace best_pace grade_adjusted_pace
      average_heart_rate max_heart_rate average_cadence max_cadence average_power
      max_power calories
    ].freeze
    MAX_RECORD_MARKERS = 32

    attr_reader :actor, :uuid, :short_id, :object_uri, :profile_snapshot,
                :privacy_zone_fingerprint, :route_metadata, :representation,
                :filtered_points_count, :has_route, :media, :media_readiness,
                :filtered, :endpoint_coverage, :endpoint_visibility

    # `photo_ids` is the owner's explicit choice of photos (nil takes every
    # ready, non-sensitive one); `photos_acknowledged` lets that choice
    # include a photo taken inside a privacy zone (PLAN_PHOTOS.md §5.2).
    def initialize(user:, workout:, profile:, photo_ids: nil, photos_acknowledged: false)
      @user = user
      @workout = workout
      @profile = profile
      @photo_ids = photo_ids
      @photos_acknowledged = photos_acknowledged
      @blobs = []
      @media = {}
      @media_readiness = {}
      @photo_copies = []
      @filtered = nil
    end

    attr_reader :photo_entries

    # A dry run (`persist_media: false`) builds the exact projection without
    # creating any identity, blob, or downloadable artifact. Media entries are
    # generated in memory only to prove readiness, then discarded.
    def prepare!(persist_media: true)
      validate_owner!
      validate_profile!
      validate_actor!
      validate_geometry!

      filtered = publication_route
      @filtered = filtered
      if persist_media
        @uuid = SecureRandom.uuid
        @short_id = Allure::ShortId.encode(@uuid)
        @object_uri = WorkoutPublication.object_uri_for(@uuid)
      end
      @profile_snapshot = {
        "audience" => @profile.audience,
        "name" => @profile.name,
        "settings" => @profile.settings.deep_dup
      }
      @privacy_zone_fingerprint = compute_privacy_zone_fingerprint
      @photo_entries = select_photos(filtered)
      # The copies come first: the snapshot records their measured size.
      @photo_copies = build_photo_copies if persist_media
      @route_metadata = {
        "bounds" => filtered.bounds,
        "segments_count" => filtered.segments.length
      }
      @representation = build_representation(filtered)
      @filtered_points_count = filtered.visible_points_count
      @has_route = filtered.usable?
      if persist_media
        @media = build_media(@short_id, filtered)
        @media_readiness = {}
      else
        @media_readiness = probe_media_readiness(filtered)
      end
      self
    rescue Allure::Federation::Privacy::ZoneFilter::InvalidInput,
           Allure::Federation::Privacy::ZoneFilter::FilteringError => error
      purge!
      raise PreparationError.new(I18n.t("workouts.publish.errors.privacy", message: error.message), code: "privacy")
    rescue Allure::Federation::Privacy::EndpointMaskPolicy::UnsatisfiedEndpoint => error
      purge!
      raise PreparationError.new(
        I18n.t("workouts.publish.errors.endpoint_mask", endpoint: I18n.t("workouts.publish.endpoints.#{error.endpoint}")),
        code: "endpoint_mask"
      )
    rescue Workouts::PublicationRoute::Unavailable => error
      purge!
      raise PreparationError.new(I18n.t("workouts.publish.errors.route_unavailable", message: error.message), code: "route_unavailable")
    rescue PublicationPhotoSelection::Unacknowledged
      purge!
      raise PreparationError.new(I18n.t("workouts.publish.errors.photos_unacknowledged"), code: "photos_unacknowledged")
    rescue Allure::Photos::Processor::Invalid, Vips::Error, ActiveStorage::FileNotFoundError
      purge!
      raise PreparationError.new(I18n.t("workouts.publish.errors.photos_unavailable"), code: "photos_unavailable")
    rescue Allure::Federation::Privacy::SanitizedGpxBuilder::Unavailable,
           Allure::Federation::Privacy::SanitizedTrackSerializer::Unavailable,
           Workouts::RouteImageRenderer::RenderingError => error
      purge!
      raise PreparationError.new(I18n.t("workouts.publish.errors.route_unavailable", message: error.message), code: "route_unavailable")
    end

    def attach_to!(publication)
      publication.gpx.attach(@media[:gpx]) if @media[:gpx]
      publication.route_image.attach(@media[:route_image]) if @media[:route_image]
      @photo_copies.each do |copy|
        publication.photos.create!(copy.except(:display, :thumbnail)).tap do |photo|
          photo.display.attach(copy[:display])
          photo.thumbnail.attach(copy[:thumbnail])
        end
      end
    end

    def purge!
      @blobs.each do |blob|
        blob.purge unless blob.attachments.exists?
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { component: self.class.name })
      end
    end

    private

    def validate_owner!
      return if @workout.user_id == @user.id

      raise ActiveRecord::RecordNotFound
    end

    def validate_actor!
      @actor = Federation::ActorProvisioner.new(user: @user).call!
      actor = @actor
      usable = actor.local? && !actor.tombstoned? && Allure::Federation.config.local_uri?(actor.uri)
      raise PreparationError.new(I18n.t("workouts.publish.errors.actor_unavailable"), code: "actor_unavailable") unless usable
    rescue Federation::ActorProvisioner::IdentityConflict
      raise PreparationError.new(I18n.t("workouts.publish.errors.actor_unavailable"), code: "actor_unavailable")
    rescue URI::InvalidURIError, Allure::Federation::Config::InvalidBaseUrl
      raise PreparationError.new(I18n.t("workouts.publish.errors.actor_unavailable"), code: "actor_unavailable")
    end

    def validate_profile!
      unless @profile.is_a?(PublishingProfile) && @profile.user_id == @user.id
        raise ActiveRecord::RecordNotFound
      end

      return if @profile.publishable?

      raise PreparationError.new(I18n.t("workouts.publish.errors.followers_unavailable"), code: "followers_unavailable")
    end

    # Until the publication contract carries a route-less Note, a positionless
    # recording is refused before any privacy work (PLAN_NO_GPS.md §7).
    def validate_geometry!
      return if @workout.positioned?

      raise PreparationError.new(I18n.t("workouts.publish.errors.no_geometry"), code: "no_geometry")
    end

    def publication_route
      route = Workouts::PublicationRoute.new(user: @user, workout: @workout, profile: @profile)
      filtered = route.call!
      @endpoint_coverage = route.endpoint_coverage
      @endpoint_visibility = route.endpoint_visibility
      filtered
    end

    def build_representation(filtered)
      route = Allure::Federation::Privacy::SanitizedTrackSerializer.new(filtered:).call
      projection = Allure::Federation::Privacy::SanitizedPublicationBuilder.new(
        settings: @profile.settings,
        title: @workout.title,
        description: @workout.description,
        metrics: workout_metrics,
        track: route,
        gpx: nil,
        route_image: nil,
        records: record_payload,
        device: @workout.source,
        commute: @workout.commute?,
        weather: (@workout.weather.summary if @workout.weather&.ready?)
      ).call

      projection.merge(
        "sport_slug" => @workout.sport.slug,
        "started_at" => @workout.started_at.iso8601(6),
        "location" => {
          "longitude" => filtered.segments.first.first.fetch(0),
          "latitude" => filtered.segments.first.first.fetch(1)
        }
      ).tap do |result|
        chart = sanitized_chart
        result["chart"] = chart if chart.present?
        photos = photo_representation
        result["photos"] = photos if photos.any?
      end
    end

    # PLAN_PHOTOS.md §5.2: the photos and what of each the profile shares.
    # Each gets its publication identity now, so the snapshot and the copies
    # name the same photo.
    PhotoEntry = Data.define(:uuid, :photo, :caption, :distance)

    def select_photos(filtered)
      PublicationPhotoSelection.new(
        workout: @workout, profile: @profile, published_segments: filtered.segments,
        selected_ids: @photo_ids, acknowledged: @photos_acknowledged
      ).call.map do |entry|
        PhotoEntry.new(uuid: SecureRandom.uuid, photo: entry.photo, caption: entry.caption, distance: entry.distance)
      end
    end

    # A dry run has no copies: it states the owner's size bounded like a copy.
    def photo_representation
      Array(@photo_entries).each_with_index.map do |entry, index|
        copy = @photo_copies[index]
        width, height = copy ? [ copy[:width], copy[:height] ] : Allure::Photos::Processor.bounded_size(entry.photo.width, entry.photo.height)
        {
          "id" => Allure::ShortId.encode(entry.uuid),
          "width" => width,
          "height" => height,
          "caption" => entry.caption,
          "distance" => entry.distance
        }.compact
      end
    end

    # Independent copies, made from the owner's already stripped display
    # file and encoded again without metadata (PLAN_PHOTOS.md §5.3).
    def build_photo_copies
      @photo_entries.each_with_index.map do |entry, position|
        copies = entry.photo.display.blob.open { |file| Allure::Photos::Processor.publication_copies(file.path) }
        display = copies.display
        thumbnail = copies.thumbnail
        begin
          {
            uuid: entry.uuid, position:, width: copies.width, height: copies.height,
            caption: entry.caption, distance: entry.distance,
            display: upload_blob(io: display, filename: "photo-#{Allure::ShortId.encode(entry.uuid)}.webp", content_type: "image/webp"),
            thumbnail: upload_blob(io: thumbnail, filename: "photo-#{Allure::ShortId.encode(entry.uuid)}-thumbnail.webp",
                                   content_type: "image/webp")
          }
        ensure
          display.close!
          thumbnail.close!
        end
      end
    end

    def workout_metrics
      PublishingProfile::METRIC_KEYS.index_with do |key|
        value = @workout.public_send(key)
        next if value.nil?

        INTEGER_METRICS.include?(key) ? value.to_i : value.to_f
      end.compact
    end

    # Markers only: which classic record types and best-effort distances this
    # workout holds. A type is published when the sport can express it and its
    # metric is enabled in the profile; distances carry no numeric value, so
    # they need no metric gate. Empty when the setting is off.
    def record_payload
      return {} unless @profile.settings["records"] == true

      payload = {}
      types = ordered_record_types
      distances = ordered_distance_keys
      payload["record_types"] = types if types.any?
      payload["record_distances"] = distances if distances.any?
      payload
    end

    def ordered_record_types
      types = @workout.records
        .select { |record| Record.visible_type?(record.record_type, @workout.sport) && metric_shared?(record.record_type) }
        .map(&:record_type).uniq
      types.sort_by { |type| Record::TYPES.index(type) || Record::TYPES.length }.first(MAX_RECORD_MARKERS)
    end

    def metric_shared?(record_type)
      metric = Record::METRIC_KEYS[record_type]
      metric.nil? || Array(@profile.settings["metrics"]).map(&:to_s).include?(metric)
    end

    def ordered_distance_keys
      keys = @workout.effort_records.map(&:distance_key).uniq
      profile = Allure::Gpx::BestEfforts.profile_for(@workout.sport.slug)
      order = profile ? Allure::Gpx::BestEfforts::PROFILES.fetch(profile) : keys
      keys.sort_by { |key| order.index(key) || order.length }.first(MAX_RECORD_MARKERS)
    end

    def sanitized_chart
      allowed = Array(@profile.settings["metrics"]).map(&:to_s)
      return [] if allowed.empty?

      Allure::Gpx::ChartSeries.new(
        workout_started_at: @workout.started_at,
        segments: @workout.track_segments
      ).call.map do |point|
        point.slice(:distance, :elapsed_time, :elevation).select do |key, _value|
          key == :distance && allowed.include?("distance") ||
            key == :elapsed_time && allowed.include?("duration") ||
            key == :elevation && allowed.any? { |metric| %w[min_elevation max_elevation].include?(metric) }
        end
      end
    end

    # Proves GPX/image generation works without persisting any blob. Keys
    # mirror the publisher settings: included, ready, and a failure reason.
    def probe_media_readiness(filtered)
      settings = @profile.settings
      {
        "gpx" => probe_gpx_readiness(settings, filtered),
        "route_image" => probe_route_image_readiness(settings, filtered)
      }
    end

    def probe_gpx_readiness(settings, filtered)
      return { "included" => false, "ready" => true, "reason" => nil } unless settings["gpx"] == true

      Allure::Federation::Privacy::SanitizedGpxBuilder.new(filtered:).call
      { "included" => true, "ready" => true, "reason" => nil }
    rescue StandardError => error
      { "included" => true, "ready" => false, "reason" => error.message }
    end

    def probe_route_image_readiness(settings, filtered)
      return { "included" => false, "ready" => true, "reason" => nil } unless settings["route_image"] == true

      image = Workouts::RouteImageRenderer.new(
        segments: filtered.segments,
        line_colour: RouteImageRenderer::TRACK_COLOUR
      ).call
      image.close! if image
      { "included" => true, "ready" => true, "reason" => nil }
    rescue StandardError => error
      { "included" => true, "ready" => false, "reason" => error.message }
    end

    # The sanitized route image is rendered after the publication exists, on the
    # dedicated route_images worker (MapLibre + OpenFreeMap, raster then
    # tile-less fallbacks). Readiness probing stays synchronous and offline.
    def build_media(publication_short_id, filtered)
      settings = @profile.settings
      media = {}
      if settings["gpx"] == true
        media[:gpx] = upload_blob(
          io: StringIO.new(Allure::Federation::Privacy::SanitizedGpxBuilder.new(filtered:).call),
          filename: "route-#{publication_short_id}.gpx",
          content_type: "application/gpx+xml"
        )
      end

      media
    end

    def upload_blob(io:, filename:, content_type:)
      io.rewind if io.respond_to?(:rewind)
      blob = ActiveStorage::Blob.create_after_unfurling!(
        io:,
        filename:,
        content_type:,
        identify: false
      )
      @blobs << blob
      blob.upload_without_unfurling(io)
      blob
    ensure
      io&.rewind
    end

    def compute_privacy_zone_fingerprint
      input = @user.privacy_zones.active.order(:id).map do |zone|
        [ zone.id, zone.longitude.to_f, zone.latitude.to_f, zone.radius_meters, zone.updated_at.to_f ]
      end
      Digest::SHA256.hexdigest(JSON.generate(input))
    end
  end
end
