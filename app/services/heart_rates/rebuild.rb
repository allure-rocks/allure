# frozen_string_literal: true

module HeartRates
  # Rebuilds one recording's heart-rate histogram (PLAN_HEART_RATE.md §3.4).
  # The pure `compute` runs before the caller's transaction (import,
  # re-analysis) or here (backfill); `persist` runs inside it, replaces the
  # row — or deletes it when no beat was recorded — slices the owner's zones,
  # and stamps `workouts.heart_rate_version`. Credit rows and manual entries
  # never get a row.
  class Rebuild
    def self.compute(segments:)
      Allure::HeartRate::Histogram.compute(segments)
    end

    def initialize(workout:)
      @workout = workout
    end

    def call
      return unless @workout.recording?

      result = self.class.compute(segments: @workout.track_segments.order(:position).to_a)
      WorkoutHeartRate.transaction { persist(result) }
      result
    end

    def persist(result)
      return unless @workout.recording?

      if result.empty?
        WorkoutHeartRate.where(workout_id: @workout.id).delete_all
        @workout.association(:heart_rate).reset
      else
        row = WorkoutHeartRate.find_or_initialize_by(workout_id: @workout.id)
        row.workout = @workout
        row.assign_attributes(
          version: Allure::HeartRate::Histogram::VERSION,
          histogram: result.histogram,
          sampled_seconds: result.sampled_seconds,
          recorded_seconds: result.recorded_seconds,
          covered_seconds: result.covered_seconds,
          frozen_seconds: result.frozen_seconds,
          sparse: result.sparse
        )
        row.assign_zones(@workout.user.heart_rate_zones)
        row.save!
      end
      @workout.update_columns(heart_rate_version: Allure::HeartRate::Histogram::VERSION)
    end
  end
end
