# frozen_string_literal: true

module Workouts
  # Freezes a workout into a publication. With the default `immediate` delay the
  # publication activates in the request path; with a safety-delay preset it is
  # created `scheduled` and nothing local or federated refers to it until
  # ScheduledPublicationActivation runs (PLAN_DELAYED_PUBLISHING.md). No outbox
  # event is created here, so cancelling inside a delay leaves no trace.
  class Publisher
    class PublicationError < StandardError
      # A stable code for programs (PLAN_API.md §6.4); the message stays the
      # translated sentence the web shows.
      attr_reader :code

      def initialize(message = nil, code: nil)
        super(message)
        @code = code
      end
    end

    # Shared by every entry point that accepts a per-publish override, so the
    # preset allowlist is the only source of valid delays.
    def self.validate_delay!(value)
      return value if PublishingProfile::PUBLISH_DELAY_VALUES.include?(value)

      raise PublicationError.new(I18n.t("workouts.publish.errors.invalid_delay"), code: "invalid_delay")
    end

    # `photo_ids`/`photos_acknowledged`: the owner's choice of photos
    # (PLAN_PHOTOS.md §5.2); nil takes every ready, non-sensitive photo.
    def initialize(user:, workout:, profile:, delay: nil, photo_ids: nil, photos_acknowledged: false)
      @user = user
      @workout = workout
      @profile = profile
      @delay = delay
      @photo_ids = photo_ids
      @photos_acknowledged = photos_acknowledged
    end

    def call!
      delay_seconds = resolve_delay!
      candidate = PublicationCandidate.new(
        user: @user, workout: @workout, profile: @profile,
        photo_ids: @photo_ids, photos_acknowledged: @photos_acknowledged
      ).prepare!

      workout_publication = nil
      WorkoutPublication.transaction do
        @workout.with_lock do
          # One live publication per audience (docs/dev/PUBLISHING.md): another
          # audience may be published beside it.
          @workout.reset_publications
          if @workout.active_publication_for(@profile.audience)
            raise PublicationError.new(I18n.t("workouts.publish.errors.already_published"), code: "already_published")
          end
          if @workout.scheduled_publication_for(@profile.audience)
            raise PublicationError.new(I18n.t("workouts.publish.errors.already_scheduled"), code: "already_scheduled")
          end

          workout_publication = @workout.workout_publications.create!(
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
            scheduled_for: Time.current + delay_seconds
          )

          candidate.attach_to!(workout_publication)
        end
      end

      @workout.reset_publications
      if delay_seconds.zero?
        Workouts::ScheduledPublicationActivation.activate_now(workout_publication)
      else
        enqueue_route_image(workout_publication)
        enqueue_activation(workout_publication)
      end
      workout_publication
    rescue PublicationCandidate::PreparationError => error
      raise PublicationError.new(error.message, code: error.code)
    rescue ActiveRecord::RecordNotUnique
      candidate&.purge!
      raise PublicationError.new(I18n.t("workouts.publish.errors.already_published"), code: "already_published")
    rescue ActiveRecord::RecordInvalid
      candidate&.purge!
      raise
    ensure
      candidate&.purge!
    end

    private

    def resolve_delay!
      self.class.validate_delay!(@delay.nil? ? @profile.publish_delay_seconds : @delay)
    end

    # The sanitized route image renders during the delay, on the dedicated
    # route_images worker, so activation usually finds it ready. A failure is
    # retried at activation and never blocks the schedule.
    def enqueue_route_image(publication)
      return unless publication.route_image_pending?

      Workouts::RenderPublicationRouteImageJob.perform_later(publication)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_publication_id: publication.id })
    end

    def enqueue_activation(publication)
      Workouts::ActivateScheduledPublicationJob
        .set(wait_until: publication.scheduled_for)
        .perform_later(publication)
    rescue StandardError => error
      # A lost enqueue is recovered by ScheduledPublicationActivation.sweep,
      # which activates due publications in the recurring federation job.
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_publication_id: publication.id })
    end
  end
end
