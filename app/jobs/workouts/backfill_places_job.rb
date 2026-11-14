# frozen_string_literal: true

module Workouts
  # Fills the workout-level place list of every currently usable toponymy in
  # bounded id-cursor batches that resume themselves. Pure and offline: it
  # assembles from the stored markers and endpoints and never re-geocodes, so it
  # is also the way to recompute the whole corpus after an assembly change.
  class BackfillPlacesJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    class << self
      def pending_scope
        Workout
          .joins(:toponymy, :sport)
          .where(sports: { virtual: false })
          .where(workout_toponymies: {
            status: %w[ready partial],
            algorithm_version: ToponymyEnricher::ALGORITHM_VERSION
          })
          .where.not(workout_toponymies: { places_algorithm_version: PlaceNamer::ALGORITHM_VERSION })
      end
    end

    def perform(after_id: 0)
      workouts = self.class.pending_scope
        .where("workouts.id > ?", after_id)
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a
      workouts.each { |workout| RebuildPlacesJob.perform_later(workout) }

      self.class.perform_later(after_id: workouts.last.id) if workouts.length == BATCH_SIZE
    end
  end
end
