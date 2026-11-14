# frozen_string_literal: true

module Workouts
  # Per-split (per-kilometre or per-mile) breakdowns from the recorded points,
  # in the viewer's unit system, or over any `interval:` in metres (the REST
  # API). Framework-independent `Allure::Gpx::Splits` does the work; this
  # service only wires the workout's persisted segments.
  class SplitsService
    def initialize(workout:, unit: nil, interval: nil)
      @workout = workout
      @unit = unit
      @interval = interval
    end

    def call
      Allure::Gpx::Splits.new(
        segments: @workout.track_segments,
        unit: @unit,
        interval: @interval,
        workout_started_at: @workout.started_at,
        stopped_speed_threshold_km_h: @workout.sport.stopped_speed_threshold,
        grade_adjusted_pace: @workout.sport.grade_adjusted_pace?,
        elevation_filter: @workout.elevation_filter
      ).call
    end
  end
end
