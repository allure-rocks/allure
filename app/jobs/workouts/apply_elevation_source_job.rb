# frozen_string_literal: true

module Workouts
  # Makes one elevation source effective for one workout: ensures the terrain
  # profile is cached when the target is `dem`, then enqueues the forced
  # reanalysis that applies it. A provider that answers nothing usable leaves
  # the effective source and the metrics untouched.
  class ApplyElevationSourceJob < ApplicationJob
    queue_as :default
    limits_concurrency key: ->(workout, *) { "workout-elevation-apply-#{workout.id}" }, duration: 10.minutes

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
              ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5
    retry_on Allure::Elevation::OpenTopoData::UnavailableError, wait: :polynomially_longer, attempts: 5
    discard_on Allure::Elevation::OpenTopoData::InvalidRequestError
    discard_on ElevationEnricher::ProviderNotConfiguredError
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    # A request that can never be satisfied must not leave the page pending
    # forever: clearing it lets the workout summary show the failed or
    # unavailable state and its retry action (docs/dev/ELEVATION.md).
    after_discard do |job, _error|
      clear_request(job.arguments.first)
    end

    def perform(workout, source)
      source = source.to_s
      return unless Workout::ELEVATION_SOURCES.include?(source)

      if source == "dem"
        Workouts::ElevationEnricher.new(workout:).call
        unless workout.reload.elevation&.status.in?(ElevationEnricher::USABLE_STATUSES)
          clear_request(workout)
          return
        end
      end

      Workouts::ReanalyzeJob.perform_later(workout, source)
    end

    private

    def clear_request(workout)
      return unless workout.is_a?(Workout)
      return if workout.elevation_source_requested.blank?

      workout.update!(elevation_source_requested: nil)
      schedule_deferred_toponymy(workout)
      schedule_deferred_weather(workout)
      AutoPublishJob.nudge(workout)
    rescue ActiveRecord::RecordNotFound
      nil
    end

    # The importer defers geocoding to the re-analysis that applies the
    # terrain profile; when that profile never comes, the recorded one is
    # final and the places are geocoded on it now.
    def schedule_deferred_toponymy(workout)
      toponymy = workout.toponymy
      return unless toponymy.nil? || toponymy.pending?

      ToponymyRefresh.new(workout:).call
    end

    # The same deferral for the weather (docs/dev/WEATHER.md).
    def schedule_deferred_weather(workout)
      weather = workout.weather
      return unless weather.nil? || weather.pending?

      WeatherRefresh.new(workout:).call
    end
  end
end
