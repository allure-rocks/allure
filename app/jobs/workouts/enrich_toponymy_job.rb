# frozen_string_literal: true

module Workouts
  class EnrichToponymyJob < ApplicationJob
    queue_as :default
    limits_concurrency to: Allure::Toponyms::Config.concurrency,
                       key: ->(*) { "workout-toponymy-geocoding" }, duration: 20.minutes

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
              ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5
    retry_on Allure::Toponyms::Nominatim::UnavailableError, wait: :polynomially_longer, attempts: 5 do |job, error|
      workout = job.arguments.first
      workout.toponymy&.update_columns(
        status: "failed",
        last_error: error.message.to_s.truncate(500),
        updated_at: Time.current
      )
      AutoPublishJob.nudge(workout)
    end
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(workout)
      ToponymyEnricher.new(workout:).call
      AutoPublishJob.nudge(workout)
    rescue StandardError => error
      Rails.error.report(error, handled: false, context: { component: self.class.name, workout_id: workout.id })
      raise
    end
  end
end
