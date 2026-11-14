# frozen_string_literal: true

module Workouts
  # Fetches one workout's weather (PLAN_WEATHER.md §5). One job at a time on
  # the instance, so the provider is paced globally; a provider outage or a
  # 429 retries with back-off and ends `failed`, an exhausted
  # daily budget waits and leaves the row pending for the recovery sweep.
  class EnrichWeatherJob < ApplicationJob
    queue_as :default
    limits_concurrency to: 1, key: ->(*) { "workout-weather" }, duration: 10.minutes

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5
    retry_on WeatherEnricher::BudgetExhaustedError, wait: 1.hour, attempts: 24
    retry_on Allure::Weather::OpenMeteo::UnavailableError,
             wait: ->(executions) { [ 30 * (2**executions), 3_600 ].min },
             attempts: 5 do |job, error|
      workout = job.arguments.first
      workout.weather&.update_columns(status: "failed", last_error: error.message.to_s.truncate(500), updated_at: Time.current)
      AutoPublishJob.nudge(workout)
    end
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(workout)
      WeatherEnricher.new(workout:).call
      AutoPublishJob.nudge(workout)
    end
  end
end
