# frozen_string_literal: true

module Workouts
  # Recurring recovery for the assistant (docs/dev/AI.md §6): re-schedules a
  # summary that failed, and one left pending past any plausible queue wait (a
  # lost job, or an exhausted budget). Only the last 30 days: an archive never
  # queues months of model calls.
  class SummaryRecoveryJob < ApplicationJob
    LIMIT = 200
    FAILED_RETRY_AFTER = 6.hours
    PENDING_RETRY_AFTER = 2.hours
    RECENT = 2.days

    queue_as :default

    class << self
      def pending_scope(now: Time.current)
        rows = WorkoutSummary.where(workout_id: SummaryEligibility.scope.select(:id))
        failed = rows.where(status: "failed", updated_at: ...(now - FAILED_RETRY_AFTER),
                            created_at: (now - RECENT)..)
        stuck = rows.where(status: "pending", updated_at: ...(now - PENDING_RETRY_AFTER))

        Workout.where(id: failed.select(:workout_id))
               .or(Workout.where(id: stuck.select(:workout_id)))
               .where(started_at: SummaryRefresh::AUTO_WINDOW.ago..)
      end
    end

    def perform
      return unless Allure::Assistant::Config.enabled?

      self.class.pending_scope.order(:id).limit(LIMIT).each do |workout|
        row = workout.assistant_summary
        # A pending row's job was lost: re-enqueue the generation itself. A
        # failed one goes back through the seam, which recomputes the facts.
        if row&.pending?
          GenerateSummaryJob.perform_later(workout)
        else
          SummaryRefresh.schedule(workout)
        end
      end
    end
  end
end
