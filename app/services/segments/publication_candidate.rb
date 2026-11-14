# frozen_string_literal: true

module Segments
  # Builds the immutable course representation, the sanitized GPX blob, and the
  # source fingerprint for a segment publication
  # (PLAN_SEGMENTS_FEDERATION.md §9.1). There is no publishing profile: the
  # segment's own visibility is the audience policy, and the corridor is never
  # zone-filtered, only consent-gated.
  class PublicationCandidate
    class PreparationError < StandardError; end

    attr_reader :actor, :uuid, :short_id, :object_uri, :representation, :route_metadata,
                :source_fingerprint, :media

    def initialize(user:, segment:)
      @user = user
      @segment = segment
      @media = {}
      @blobs = []
    end

    def prepare!(persist_media: true)
      validate_owner!
      validate_shareable!
      validate_corridor!
      validate_actor!

      if persist_media
        @uuid = SecureRandom.uuid
        @short_id = Allure::ShortId.encode(@uuid)
        @object_uri = SegmentPublication.object_uri_for(@uuid)
      end
      @coordinates = coordinates
      @representation = build_representation
      @route_metadata = { "bounds" => @segment.bounds, "segments_count" => 1 }
      @source_fingerprint = @segment.publication_fingerprint
      @media[:gpx] = build_gpx(@short_id) if persist_media
      self
    rescue StandardError
      purge!
      raise
    end

    def attach_to!(publication)
      publication.gpx.attach(@media[:gpx]) if @media[:gpx]
      publication
    end

    # Purges every blob this candidate created that is not attached to a
    # publication (failed persist, invalid record, rejected request).
    def purge!
      @blobs.each do |blob|
        next if blob.attachments.exists?

        blob.purge
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { component: self.class.name })
      end
      @blobs.clear
      @media = {}
    end

    private

    def validate_owner!
      raise ActiveRecord::RecordNotFound unless @segment.user_id == @user.id
    end

    def validate_shareable!
      return if @segment.shareable?

      raise PreparationError, I18n.t("segments.publish.errors.not_shareable")
    end

    def validate_corridor!
      return unless Segments::CorridorPreflight.intersects?(@segment)
      return if @segment.privacy_zone_acknowledged_at.present?

      raise PreparationError, I18n.t("segments.publish.errors.corridor_acknowledgment")
    end

    def validate_actor!
      @actor = Federation::ActorProvisioner.new(user: @user).call!
      usable = @actor.local? && !@actor.tombstoned? && Allure::Federation.config.local_uri?(@actor.uri)
      raise PreparationError, I18n.t("segments.publish.errors.actor_unavailable") unless usable
    end

    def coordinates
      points = @segment.geom.points.map { |point| [ point.x, point.y ] }
      raise PreparationError, I18n.t("segments.publish.errors.route_unavailable") if points.length < 2

      points
    end

    def filtered_track
      Allure::Federation::Privacy::FilteredTrack.new(
        segments: [ @coordinates ],
        visible_points_count: @coordinates.length,
        points_removed: false,
        interior_points_removed: false,
        bounds: @segment.bounds,
        usable: true
      )
    end

    def build_representation
      track = Allure::Federation::Privacy::SanitizedTrackSerializer.new(filtered: filtered_track).call
      representation = {
        "name" => @segment.name,
        "kind" => "segment",
        "distance" => @segment.distance.to_f,
        "match_tolerance" => @segment.match_tolerance_meters,
        "track" => track,
        "location" => { "longitude" => @coordinates.first[0], "latitude" => @coordinates.first[1] }
      }
      representation["description"] = @segment.description if @segment.description.present?
      representation["sport_slug"] = @segment.sport.slug if @segment.sport
      representation["ascent"] = @segment.ascent.to_f unless @segment.ascent.nil?
      representation["descent"] = @segment.descent.to_f unless @segment.descent.nil?
      representation["average_grade"] = @segment.average_grade.to_f unless @segment.average_grade.nil?
      representation.deep_stringify_keys
    rescue Allure::Federation::Privacy::SanitizedTrackSerializer::Unavailable => error
      raise PreparationError, I18n.t("segments.publish.errors.route_unavailable", message: error.message)
    end

    def build_gpx(short_id)
      xml = Allure::Federation::Privacy::SanitizedGpxBuilder.new(filtered: filtered_track).call
      upload_blob(io: StringIO.new(xml), filename: "segment-#{short_id}.gpx", content_type: "application/gpx+xml")
    rescue Allure::Federation::Privacy::SanitizedGpxBuilder::Unavailable => error
      raise PreparationError, I18n.t("segments.publish.errors.route_unavailable", message: error.message)
    end

    def upload_blob(io:, filename:, content_type:)
      io.rewind if io.respond_to?(:rewind)
      blob = ActiveStorage::Blob.create_after_unfurling!(io:, filename:, content_type:, identify: false)
      @blobs << blob
      blob.upload_without_unfurling(io)
      blob
    ensure
      io&.rewind
    end
  end
end
