# frozen_string_literal: true

module Workouts
  # Schedules, in bounded id-cursor batches that resume themselves, the
  # assistant summary of every eligible workout of the last 30 days whose row is
  # missing, failed, or built by an older generation (docs/dev/AI.md §6). It
  # only schedules: the generation queue paces the model.
  class BackfillSummariesJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    class << self
      def pending_scope
        return Workout.none unless Allure::Assistant::Config.enabled?

        SummaryEligibility.scope
          .where(started_at: SummaryRefresh::AUTO_WINDOW.ago..)
          .left_joins(:assistant_summary)
          .where(
            "workout_summaries.id IS NULL OR workout_summaries.status = 'failed' " \
            "OR workout_summaries.version < ?",
            Allure::Insights::VERSION
          )
      end
    end

    def perform(after_id: 0, user_id: nil)
      scope = self.class.pending_scope
      scope = scope.where(user_id:) if user_id
      workouts = scope.where("workouts.id > ?", after_id).order(:id).limit(BATCH_SIZE).to_a
      workouts.each { |workout| SummaryRefresh.schedule(workout) }

      self.class.perform_later(after_id: workouts.last.id, user_id:) if workouts.length == BATCH_SIZE
    end
  end
end
