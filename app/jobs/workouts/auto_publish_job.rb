# frozen_string_literal: true

module Workouts
  # Settles a workout's waiting automatic publications
  # (docs/dev/AUTO-PUBLISHING.md). Enqueued by the importer and nudged by every
  # enrichment job when it finishes; the recurring sweep recovers a lost nudge
  # and applies the deadline. Running it early is harmless: it does nothing
  # until the workout is ready.
  class AutoPublishJob < ApplicationJob
    queue_as :default
    limits_concurrency key: ->(workout, **) { "workout-auto-publish-#{workout.id}" }, duration: 10.minutes

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    # The single seam the enrichment jobs call: a workout with nothing waiting
    # costs one indexed lookup and enqueues nothing. The same moment tells the
    # owner's webhooks the analysis settled (docs/dev/API.md).
    def self.nudge(workout)
      return unless workout.is_a?(Workout)

      Webhooks::Events.workout_analyzed(workout)
      return unless WorkoutAutoPublication.waiting.exists?(workout_id: workout.id)

      perform_later(workout)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: name, workout_id: workout&.id })
    end

    def perform(workout)
      AutoPublisher.new(workout:).call
    end
  end
end
