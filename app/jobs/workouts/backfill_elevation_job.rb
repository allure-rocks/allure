# frozen_string_literal: true

module Workouts
  # Enqueues the terrain-elevation apply job for every elevation-less workout of
  # an opted-in owner, in bounded id-cursor batches that resume themselves
  # (PLAN_ELEVATION.md §7). Only runs when the instance configures a provider.
  class BackfillElevationJob < ApplicationJob
    BATCH_SIZE = 50

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    class << self
      # A credit row and a positionless recording have no track to sample
      # (PLAN_TOGETHER.md §6.6, PLAN_NO_GPS.md §6).
      def pending_scope
        Workout.positioned
          .where(recorded_elevation: false)
          .joins(:sport, :user)
          .where(sports: { records_elevation: true }, users: { elevation_enrichment_enabled: true })
          .where.not(
            id: WorkoutElevation.where(status: ElevationEnricher::USABLE_STATUSES).select(:workout_id)
          )
      end
    end

    def perform(after_id: 0)
      return unless Allure::Elevation::Config.configured?

      workouts = self.class.pending_scope
        .where("workouts.id > ?", after_id)
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a
      workouts.each { |workout| ApplyElevationSourceJob.perform_later(workout, "dem") }

      self.class.perform_later(after_id: workouts.last.id) if workouts.length == BATCH_SIZE
    end
  end
end
