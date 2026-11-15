# frozen_string_literal: true

module Workouts
  # Replaces one active publication with a new frozen snapshot. The old
  # publication is withdrawn immediately and the replacement enters the safety
  # delay (PLAN_DELAYED_PUBLISHING.md): a replacement intended to remove
  # sensitive data takes effect at once, and the new representation is held for
  # review before anyone sees it. The other audiences' publications are left
  # alone (docs/dev/PUBLISHING.md); the replacement keeps the replaced audience or
  # takes one no other live publication holds.
  class PublicationReplacement
    Result = Data.define(:old_publication, :new_publication, :delete_event)

    # `publication:` names the active publication to replace; without it, the
    # one sharing the new profile's audience, else the only active one.
    def initialize(user:, workout:, profile:, delay: nil, publication: nil, photo_ids: nil, photos_acknowledged: false)
      @user = user
      @workout = workout
      @profile = profile
      @delay = delay
      @replaced = publication
      @photo_ids = photo_ids
      @photos_acknowledged = photos_acknowledged
    end

    def call!
      raise ActiveRecord::RecordNotFound unless @workout.user_id == @user.id

      delay_seconds = Publisher.validate_delay!(@delay.nil? ? @profile.publish_delay_seconds : @delay)
      @workout.reset_publications
      old_publication = replaced_publication
      raise ActiveRecord::RecordNotFound unless old_publication

      candidate = PublicationCandidate.new(
        user: @user, workout: @workout, profile: @profile,
        photo_ids: @photo_ids, photos_acknowledged: @photos_acknowledged
      ).prepare!
      begin
        result = activate_replacement!(old_publication, candidate, delay_seconds)
      rescue StandardError
        candidate.purge!
        raise
      else
        candidate.purge!
        result
      end
    rescue PublicationCandidate::PreparationError => error
      raise Publisher::PublicationError.new(error.message, code: error.code)
    end

    private

    def replaced_publication
      active = @workout.active_publications.to_a
      return active.find { |publication| publication.id == @replaced.id } if @replaced

      @workout.active_publication_for(@profile.audience) || (active.first if active.one?)
    end

    # Another live publication already holding the new audience would make
    # two versions of one audience.
    def audience_taken?(old_publication)
      @workout.reset_publications
      @workout.live_audiences.include?(@profile.audience) && old_publication.audience != @profile.audience
    end

    def activate_replacement!(old_publication, candidate, delay_seconds)
      new_publication = nil
      delete_event = nil
      scheduled_for = Time.current + delay_seconds

      WorkoutPublication.transaction do
        candidate.actor.with_lock do
          @workout.with_lock do
            @workout.reset_publications
            current = @workout.active_publications.find { |publication| publication.id == old_publication.id }
            unless current&.active?
              raise ActiveRecord::RecordNotFound, "active publication changed during replacement"
            end
            if audience_taken?(current)
              raise Publisher::PublicationError.new(I18n.t("workouts.publish.errors.audience_taken"), code: "audience_taken")
            end

            current.lock!
            old_create = PublicationWithdrawal.find_create_event(current)
            recipient_uris = PublicationWithdrawal.recipient_uris_for(old_create)
            PublicationWithdrawal.cancel_unattempted!(old_create)
            delete_event = find_or_create_delete_event!(current, candidate.actor, recipient_uris)
            current.mark_deleted!
            Webhooks::Events.publication_withdrawn(current, reason: "replaced")
            reconcile_create_event!(old_create, recipient_uris)

            new_publication = @workout.workout_publications.create!(
              actor: candidate.actor,
              uuid: candidate.uuid,
              object_uri: candidate.object_uri,
              publishing_profile: @profile,
              profile_snapshot: candidate.profile_snapshot,
              privacy_zone_fingerprint: candidate.privacy_zone_fingerprint,
              route_metadata: candidate.route_metadata,
              representation: candidate.representation,
              filtered_points_count: candidate.filtered_points_count,
              has_route: candidate.has_route,
              sanitized_gpx_blob_id: candidate.media[:gpx]&.id,
              status: "scheduled",
              scheduled_for:
            )
            candidate.attach_to!(new_publication)
          end
        end
      end

      @workout.reset_publications
      PublicationWithdrawal.enqueue_expansion(delete_event)
      if delay_seconds.zero?
        Workouts::ScheduledPublicationActivation.activate_now(new_publication)
      else
        enqueue_route_image(new_publication)
        Workouts::ScheduledPublicationActivation.enqueue_job(new_publication)
      end
      Result.new(
        old_publication: old_publication.reload,
        new_publication:,
        delete_event:
      )
    end

    def find_or_create_delete_event!(publication, actor, recipient_uris)
      existing = FederationOutboxEvent.find_by(
        subject_type: "WorkoutPublication",
        subject_id: publication.id,
        workout_publication_id: publication.id,
        object_uri: publication.object_uri,
        activity_type: "Delete"
      )
      return existing if existing

      Federation::Outbox::EventBuilder.new(
        actor:,
        subject_type: "WorkoutPublication",
        subject_id: publication.id,
        workout_publication_id: publication.id,
        activity_type: "Delete",
        object_uri: publication.object_uri,
        idempotency_key: "publication:delete:#{publication.object_uri}",
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
        subject_type: "WorkoutPublication",
        subject_id: publication.id,
        object_uri: publication.object_uri,
        activity_type: "Delete"
      )
    end

    def reconcile_create_event!(create_event, recipient_uris)
      return unless create_event
      return if recipient_uris.any?
      return if create_event.terminal?

      create_event.mark_cancelled!(reason: "publication replaced before any delivery attempt")
    end

    def enqueue_route_image(publication)
      return unless publication.route_image_pending?

      Workouts::RenderPublicationRouteImageJob.perform_later(publication)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_publication_id: publication&.id })
    end
  end
end
