# frozen_string_literal: true

module Workouts
  # Sweeps every workout whose stored analysis or import-detection generation
  # is older than the current one through Workouts::RebuildJob, in bounded
  # id-cursor batches that resume themselves (PLAN_DERIVATIONS.md §5).
  # Idempotent and safe to re-run: each workout is reconciled against its own
  # immutable file, so a new analyzer or a new virtual platform is a constant
  # bump plus one run of this sweep.
  class BackfillRebuildJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    class << self
      # Only workouts that still keep their original file can be reconciled:
      # a fileless workout has nothing to re-read and is deliberately never
      # counted (it would otherwise stay pending forever).
      def pending_scope
        Workout
          .joins(:original_file_attachment)
          .where(
            "analysis_version < :analysis OR import_detection_version < :detection",
            analysis: Allure::Gpx::Analyzer::VERSION,
            detection: ImportDetection::VERSION
          )
      end
    end

    def perform(after_id: 0)
      workouts = self.class.pending_scope
        .where("workouts.id > ?", after_id)
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a

      workouts.each { |workout| RebuildJob.perform_later(workout) }

      self.class.perform_later(after_id: workouts.last.id) if workouts.length == BATCH_SIZE
    end
  end
end
