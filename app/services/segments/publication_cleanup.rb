# frozen_string_literal: true

module Segments
  # Terminal cleanup for a withdrawn course publication: once every related
  # outbox event and delivery is terminal, the sanitized media is purged, the
  # representation is reduced to a redacted audit snapshot, and the related
  # payloads are redacted. Mirrors Workouts::PublicationCleanup.
  class PublicationCleanup
    class NotEligible < StandardError; end

    Result = Data.define(:publication, :cleaned)

    SWEEP_LIMIT = 100

    def initialize(publication:, now: Time.current)
      @publication = publication
      @now = now
    end

    def self.sweep(limit: SWEEP_LIMIT)
      cleaned = 0
      SegmentPublication.deleted.where(location_data_purged_at: nil)
        .order(:updated_at, :id).limit(limit).each do |publication|
        new(publication:).call!
        cleaned += 1
      rescue NotEligible
        next
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { component: name, segment_publication_id: publication.id })
        next
      end
      cleaned
    end

    def call!
      @publication.with_lock do
        @publication.reload
        return Result.new(publication: @publication, cleaned: false) if fully_cleaned?
        raise NotEligible, "publication is not eligible for location cleanup" unless eligible?

        write_redacted_snapshot!
        purge_media!
        redact_related_payloads!
        Result.new(publication: @publication.reload, cleaned: true)
      end
    end

    def self.eligible?(publication)
      return false unless publication.deleted?

      related_events(publication).all? do |event|
        event.terminal? && event.deliveries.all?(&:terminal?)
      end
    end

    def self.related_events(publication)
      FederationOutboxEvent.where(segment_publication_id: publication.id).order(:created_at, :id)
    end

    private

    def eligible? = self.class.eligible?(@publication)

    def fully_cleaned?
      @publication.location_data_purged_at.present? &&
        !@publication.gpx.attached? && !@publication.route_image.attached? && !@publication.route_image_dark.attached? &&
        @publication.sanitized_gpx_blob_id.nil? && @publication.sanitized_route_image_blob_id.nil? &&
        @publication.sanitized_route_image_dark_blob_id.nil?
    end

    def purge_media!
      @publication.gpx.purge if @publication.gpx.attached?
      @publication.route_image.purge if @publication.route_image.attached?
      @publication.route_image_dark.purge if @publication.route_image_dark.attached?
    end

    def write_redacted_snapshot!
      representation = @publication.representation
      redacted_representation = {
        "name" => representation["name"],
        "description" => representation["description"],
        "sport_slug" => representation["sport_slug"],
        "kind" => representation["kind"],
        "distance" => representation["distance"],
        "ascent" => representation["ascent"],
        "descent" => representation["descent"],
        "average_grade" => representation["average_grade"],
        "match_tolerance" => representation["match_tolerance"],
        "redacted" => true
      }
      # Immutable snapshot columns are written through the relation: cleanup is
      # the controlled terminal exception to publication immutability.
      SegmentPublication.where(id: @publication.id).update_all(
        representation: redacted_representation,
        route_metadata: { "redacted" => true },
        sanitized_gpx_blob_id: nil,
        sanitized_route_image_blob_id: nil,
        sanitized_route_image_dark_blob_id: nil,
        location_data_purged_at: @now,
        updated_at: @now
      )
    end

    def redact_related_payloads!
      self.class.related_events(@publication).each do |event|
        Federation::Outbox::PayloadRedactor.new(event:, now: @now).call!
      end
    end
  end
end
