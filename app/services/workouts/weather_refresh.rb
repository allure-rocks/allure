# frozen_string_literal: true

module Workouts
  # The single server-side way to (re)schedule a workout's weather
  # (docs/dev/WEATHER.md), like `ToponymyRefresh`. It marks the row pending and
  # enqueues the paced job. A workout that can no longer have weather (a sport
  # turned virtual) loses any stored row; one whose owner withdrew consent
  # keeps it untouched and asks nothing.
  class WeatherRefresh
    def initialize(workout:)
      @workout = workout
    end

    def call
      reason = WeatherEligibility.reason(@workout)
      if WeatherEligibility::STRUCTURAL.include?(reason)
        discard
        return nil
      end
      return nil if reason

      record = mark_pending
      enqueue(record)
      record
    end

    private

    def discard
      @workout.weather&.destroy!
      @workout.update_columns(weather_start: nil, weather_end: nil) if @workout.weather_start || @workout.weather_end
    end

    def mark_pending
      record = @workout.weather || @workout.create_weather!(status: "pending")
      record.update!(status: "pending", last_error: nil, updated_at: Time.current)
      record
    rescue ActiveRecord::RecordNotUnique
      @workout.association(:weather).reload
      retry
    end

    def enqueue(record)
      EnrichWeatherJob.perform_later(@workout)
    rescue StandardError => error
      record.update_columns(status: "failed", last_error: error.message.to_s.truncate(500), updated_at: Time.current)
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: @workout.id })
    end
  end
end
