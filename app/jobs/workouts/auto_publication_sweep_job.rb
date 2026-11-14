# frozen_string_literal: true

module Workouts
  # Recurring recovery for automatic publishing (PLAN_AUTO_PUBLISHING.md §5):
  # re-runs every workout that still has a waiting row, so a lost nudge is
  # recovered and an overdue wait fails with its notification.
  class AutoPublicationSweepJob < ApplicationJob
    LIMIT = 500

    queue_as :default

    def perform
      workout_ids = WorkoutAutoPublication.waiting.group(:workout_id)
        .order(Arel.sql("MIN(deadline_at)")).limit(LIMIT).pluck(:workout_id)
      Workout.where(id: workout_ids).find_each { |workout| AutoPublishJob.perform_later(workout) }
    end
  end
end
