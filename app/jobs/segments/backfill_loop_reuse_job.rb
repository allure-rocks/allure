# frozen_string_literal: true

module Segments
  # Re-runs loop detection for every positioned recording with an older
  # detection/reuse generation, including recordings with no loop yet
  # (docs/dev/DERIVATIONS.md). Because
  # `LoopReuse` always elects the oldest similar loop, re-running the matches
  # converges duplicate loops of one account onto a single segment instead of
  # creating new ones. Bounded id-cursor batches that resume themselves; a
  # converged instance re-runs nothing.
  class BackfillLoopReuseJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    class << self
      def pending_scope
        Workout.recordings.positioned
          .where(loop_reuse_version: ...LoopReuse::VERSION)
      end
    end

    def perform(after_id: 0)
      workouts = self.class.pending_scope
        .where("workouts.id > ?", after_id)
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a

      workouts.each { |workout| MatchWorkoutJob.perform_later(workout) }

      self.class.perform_later(after_id: workouts.last.id) if workouts.length == BATCH_SIZE
    end
  end
end
