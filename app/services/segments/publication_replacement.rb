# frozen_string_literal: true

module Segments
  # Atomically replaces the active course publication with a new immutable
  # identity: the new Create and the old Delete are decided in one transaction
  # (PLAN_SEGMENTS_FEDERATION.md §9.3).
  class PublicationReplacement
    Result = Data.define(:old_publication, :new_publication, :delete_event, :create_event)

    def initialize(user:, segment:)
      @user = user
      @segment = segment
    end

    def call!
      raise ActiveRecord::RecordNotFound unless @segment.user_id == @user.id

      @segment.association(:active_publication).reset
      old_publication = @segment.active_publication
      raise ActiveRecord::RecordNotFound unless old_publication

      candidate = PublicationCandidate.new(user: @user, segment: @segment).prepare!
      begin
        result = activate_replacement!(old_publication, candidate)
      rescue StandardError
        candidate.purge!
        raise
      else
        candidate.purge!
        result
      end
    rescue PublicationCandidate::PreparationError => error
      raise Publisher::PublicationError, error.message
    end

    private

    def activate_replacement!(old_publication, candidate)
      new_publication = nil
      delete_event = nil
      create_event = nil

      SegmentPublication.transaction do
        candidate.actor.with_lock do
          @segment.with_lock do
            @segment.association(:active_publication).reset
            current = @segment.active_publication
            unless current && current.id == old_publication.id && current.active?
              raise ActiveRecord::RecordNotFound, "active publication changed during replacement"
            end

            current.lock!
            old_create = PublicationWithdrawal.find_create_event(current)
            recipient_uris = PublicationWithdrawal.recipient_uris_for(old_create)
            PublicationWithdrawal.cancel_unattempted!(old_create)
            delete_event = find_or_create_delete_event!(current, candidate.actor, recipient_uris)
            current.mark_deleted!
            reconcile_create_event!(old_create, recipient_uris)

            new_publication = @segment.segment_publications.create!(
              actor: candidate.actor,
              uuid: candidate.uuid,
              object_uri: candidate.object_uri,
              audience: audience,
              representation: candidate.representation,
              route_metadata: candidate.route_metadata,
              source_fingerprint: candidate.source_fingerprint,
              sanitized_gpx_blob_id: candidate.media[:gpx]&.id
            )
            candidate.attach_to!(new_publication)
            create_event = create_create_event!(new_publication)
          end
        end
      end

      @segment.association(:active_publication).reset
      enqueue_expansion(delete_event)
      if create_event.preparing?
        enqueue_route_image(new_publication)
      else
        enqueue_expansion(create_event)
      end
      Result.new(
        old_publication: old_publication.reload,
        new_publication:,
        delete_event:,
        create_event:
      )
    end

    def audience
      @segment.visibility == "followers_only" ? "followers" : "public"
    end

    def find_or_create_delete_event!(publication, actor, recipient_uris)
      existing = PublicationWithdrawal.find_delete_event(publication)
      return existing if existing

      Federation::Outbox::EventBuilder.new(
        actor:,
        subject_type: "SegmentPublication",
        subject_id: publication.id,
        segment_publication_id: publication.id,
        activity_type: "Delete",
        object_uri: publication.object_uri,
        idempotency_key: "segment_publication:delete:#{publication.object_uri}",
        payload: {
          "type" => "Delete",
          "actor" => actor.uri,
          "object" => publication.object_uri,
          "to" => recipient_uris,
          "cc" => []
        },
        audience: { "recipients" => recipient_uris, "to" => recipient_uris, "cc" => [] }
      ).call!
    rescue Federation::Outbox::EventBuilder::IdentityConflict
      FederationOutboxEvent.find_by!(
        subject_type: "SegmentPublication",
        subject_id: publication.id,
        object_uri: publication.object_uri,
        activity_type: "Delete"
      )
    end

    # Mirrors the initial publish: a Create whose route image is still being
    # rendered stays `preparing` until the render job finalizes it.
    def create_create_event!(publication)
      status = publication.route_image_pending? ? "preparing" : "pending"
      Federation::Outbox::SegmentCreate.new(publication:).intent!(status:)
    end

    def reconcile_create_event!(create_event, recipient_uris)
      return unless create_event
      return if recipient_uris.any?
      return if create_event.terminal?

      create_event.mark_cancelled!(reason: "segment publication replaced before any delivery attempt")
    end

    def enqueue_expansion(event)
      return unless Allure::Federation::Config.enabled? && event&.pending?

      Federation::ExpandOutboxEventJob.perform_later(event)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name })
    end

    def enqueue_route_image(publication)
      Segments::RenderPublicationRouteImageJob.perform_later(publication)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: {
        component: self.class.name, segment_publication_id: publication&.id
      })
    end
  end
end
