# frozen_string_literal: true

module Workouts
  # Recurring recovery for geocoding (docs/dev/DERIVATIONS.md): reschedules a
  # recent toponymy that failed, and one left pending past any plausible queue
  # wait (a lost job, or a deferred import whose terrain re-analysis kept the
  # recorded profile). Older failures are left to the owner's « Lieux » action
  # and the operator's sweep, so a place Nominatim cannot name is not asked
  # about forever.
  class ToponymyRecoveryJob < ApplicationJob
    LIMIT = 200
    FAILED_RETRY_AFTER = 6.hours
    PENDING_RETRY_AFTER = 2.hours
    RECENT = 2.days

    queue_as :default

    class << self
      def pending_scope(now: Time.current)
        toponymies = WorkoutToponymy
          .joins(workout: :sport)
          .where(sports: { virtual: false }, workouts: { elevation_source_requested: nil })
        failed = toponymies.where(status: "failed", updated_at: ...(now - FAILED_RETRY_AFTER), created_at: (now - RECENT)..)
        stuck = toponymies.where(status: "pending", updated_at: ...(now - PENDING_RETRY_AFTER))

        Workout.where(id: failed.select(:workout_id)).or(Workout.where(id: stuck.select(:workout_id)))
      end
    end

    def perform
      return unless Allure::Toponyms::Config.configured?

      self.class.pending_scope.order(:id).limit(LIMIT).each do |workout|
        ToponymyRefresh.new(workout:).call
      end
    end
  end
end
