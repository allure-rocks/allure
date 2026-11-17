# frozen_string_literal: true

module Workouts
  # The weather channels of the owner's profile chart (docs/dev/WEATHER.md):
  # one `{ temperature:, headwind: }` per stored point, in the global point
  # order `Allure::Gpx::ChartSeries` reads, or nil when the workout has no
  # ready weather. Owner-only, like every other stored channel.
  module WeatherChartValues
    KEYS = %i[temperature headwind].freeze

    module_function

    def call(workout)
      weather = workout.weather
      return nil unless weather&.ready?

      rows = weather.series_values
      return nil unless rows.any?(&:usable?)

      points = Allure::Segments::PointStream.new(segments: workout.track_segments, workout_started_at: workout.started_at).call
      Allure::Weather::PointValues.new(
        points:, rows:, stopped_speed_threshold_mps: workout.sport.stopped_speed_threshold.to_f / 3.6
      ).call
    end
  end
end
