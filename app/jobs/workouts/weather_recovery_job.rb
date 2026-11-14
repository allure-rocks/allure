# frozen_string_literal: true

module Workouts
  # Recurring recovery for weather (PLAN_WEATHER.md §5): reschedules a recent
  # weather that failed, and one left pending past any plausible queue wait
  # (a lost job, or a budget that ran out). Older failures are left to the
  # owner's « Actualiser la météo » action and the operator's sweep.
  class WeatherRecoveryJob < ApplicationJob
    LIMIT = 200
    FAILED_RETRY_AFTER = 6.hours
    PENDING_RETRY_AFTER = 2.hours
    RECENT = 2.days

    queue_as :default

    class << self
      def pending_scope(now: Time.current)
        weathers = WorkoutWeather.where(workout_id: WeatherEligibility.scope.select(:id))
        failed = weathers.where(status: "failed", updated_at: ...(now - FAILED_RETRY_AFTER), created_at: (now - RECENT)..)
        stuck = weathers.where(status: "pending", updated_at: ...(now - PENDING_RETRY_AFTER))

        Workout.where(id: failed.select(:workout_id)).or(Workout.where(id: stuck.select(:workout_id)))
      end
    end

    def perform
      return unless Allure::Weather::Config.enabled?

      self.class.pending_scope.order(:id).limit(LIMIT).each do |workout|
        WeatherRefresh.new(workout:).call
      end
    end
  end
end
