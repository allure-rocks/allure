# frozen_string_literal: true

module Workouts
  # Moves a scheduled publication's planned moment to another preset within the
  # safety delay (PLAN_DELAYED_PUBLISHING.md §4). The frozen snapshot does not
  # change; only the activation job is re-enqueued. An in-flight job that fires
  # before the new moment defers itself.
  class ScheduledPublicationReschedule
    Result = Data.define(:publication, :scheduled_for)

    # `publication:` names the scheduled publication; without it, the only one.
    def initialize(user:, workout:, delay:, publication: nil, now: Time.current)
      @user = user
      @workout = workout
      @delay = delay
      @given_publication = publication
      @now = now
    end

    def call!
      raise ActiveRecord::RecordNotFound unless @workout.user_id == @user.id

      seconds = Publisher.validate_delay!(@delay)
      publication = resolve_publication
      raise ActiveRecord::RecordNotFound unless publication

      scheduled_for = nil
      publication.with_lock do
        publication.reload
        raise ActiveRecord::RecordNotFound unless publication.scheduled?

        scheduled_for = @now + seconds
        publication.update!(scheduled_for:)
      end

      enqueue_activation(publication)
      Result.new(publication:, scheduled_for:)
    end

    private

    def resolve_publication
      @workout.reset_publications
      scheduled = @workout.scheduled_publications.to_a
      return scheduled.find { |publication| publication.id == @given_publication.id } if @given_publication
      raise ArgumentError, "several scheduled publications: name the one to reschedule" if scheduled.many?

      scheduled.first
    end

    def enqueue_activation(publication)
      Workouts::ActivateScheduledPublicationJob
        .set(wait_until: publication.scheduled_for)
        .perform_later(publication)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_publication_id: publication.id })
    end
  end
end
