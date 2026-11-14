# frozen_string_literal: true

module Workouts
  # Schedules, in bounded id-cursor batches that resume themselves, the
  # weather of every eligible workout of a consenting account that has none,
  # or whose row was built by an older fetch or analysis generation
  # (PLAN_WEATHER.md §5). It only schedules: the weather job is paced, and a
  # new analysis generation converges offline from the kept responses.
  class BackfillWeatherJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    class << self
      def pending_scope
        return Workout.none unless Allure::Weather::Config.enabled?

        WeatherEligibility.scope
          .left_joins(:weather)
          .where(
            "workout_weathers.id IS NULL OR (workout_weathers.status <> 'pending' AND " \
            "(workout_weathers.fetch_version < :fetch OR workout_weathers.analysis_version < :analysis))",
            fetch: WeatherEnricher::FETCH_VERSION, analysis: WeatherEnricher::ANALYSIS_VERSION
          )
      end
    end

    def perform(after_id: 0, user_id: nil)
      scope = self.class.pending_scope
      scope = scope.where(user_id:) if user_id
      workouts = scope.where("workouts.id > ?", after_id).order(:id).limit(BATCH_SIZE).to_a
      workouts.each { |workout| WeatherRefresh.new(workout:).call }

      self.class.perform_later(after_id: workouts.last.id, user_id:) if workouts.length == BATCH_SIZE
    end
  end
end
