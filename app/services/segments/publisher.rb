# frozen_string_literal: true

module Segments
  # Publishes a segment as an immutable course representation and emits its
  # Create intent (docs/dev/SEGMENTS-FEDERATION.md). There is no publishing
  # profile: the publication audience is snapshotted from `visibility`.
  class Publisher
    class PublicationError < StandardError; end

    def initialize(user:, segment:)
      @user = user
      @segment = segment
    end

    def call!
      candidate = PublicationCandidate.new(user: @user, segment: @segment)
      candidate.prepare!

      publication = nil
      event = nil
      SegmentPublication.transaction do
        @segment.with_lock do
          if @segment.segment_publications.active.exists?
            raise PublicationError, I18n.t("segments.publish.errors.already_published")
          end

          publication = @segment.segment_publications.create!(
            actor: candidate.actor,
            uuid: candidate.uuid,
            object_uri: candidate.object_uri,
            audience: audience,
            representation: candidate.representation,
            route_metadata: candidate.route_metadata,
            source_fingerprint: candidate.source_fingerprint,
            sanitized_gpx_blob_id: candidate.media[:gpx]&.id
          )
          candidate.attach_to!(publication)
          event = create_outbox_event!(publication)
        end
      end

      @segment.association(:active_publication).reset
      if publication.route_image_pending?
        enqueue_route_image(publication)
      else
        enqueue_expansion(event)
      end
      publication
    rescue PublicationCandidate::PreparationError => error
      raise PublicationError, error.message
    rescue ActiveRecord::RecordNotUnique
      candidate.purge!
      raise PublicationError, I18n.t("segments.publish.errors.already_published")
    ensure
      candidate&.purge!
    end

    private

    def audience
      @segment.visibility == "followers_only" ? "followers" : "public"
    end

    def create_outbox_event!(publication)
      status = publication.route_image_pending? ? "preparing" : "pending"
      Federation::Outbox::SegmentCreate.new(publication:).intent!(status:)
    end

    def enqueue_route_image(publication)
      Segments::RenderPublicationRouteImageJob.perform_later(publication)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: {
        component: self.class.name, segment_publication_id: publication.id
      })
    end

    def enqueue_expansion(event)
      return unless Allure::Federation::Config.enabled? && event&.pending?

      Federation::ExpandOutboxEventJob.perform_later(event)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name })
    end
  end
end
