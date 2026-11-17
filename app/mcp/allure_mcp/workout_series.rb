# frozen_string_literal: true

module AllureMcp
  # A workout's recorded measurements over distance and time, as a compact
  # table (docs/dev/MCP.md): never a coordinate. The points come from
  # Allure::Gpx::ChartSeries, which keeps every extremum and every gap
  # boundary when it thins a range down to `max_points`.
  class WorkoutSeries
    SERIES = %i[elevation speed heart_rate cadence power].freeze
    DEFAULT_POINTS = 300
    MAX_POINTS = 2_000

    def initialize(workout, series: nil, from_distance: nil, to_distance: nil, from_time: nil, to_time: nil,
                   max_points: DEFAULT_POINTS)
      @workout = workout
      @requested = series&.map(&:to_sym)
      @from_distance = from_distance
      @to_distance = to_distance
      @from_time = from_time
      @to_time = to_time
      @max_points = max_points.to_i.clamp(2, MAX_POINTS)
    end

    def call
      segments = @workout.track_segments.to_a
      points = Allure::Gpx::ChartSeries.new(
        workout_started_at: @workout.started_at, segments:, max_points: Float::INFINITY,
        include_index: true, series: SERIES
      ).call
      recorded = SERIES.select { |key| points.any? { !it[key].nil? } }
      chosen = @requested ? SERIES & @requested & recorded : recorded
      selected = points.select { in_range?(it) }
      bounded = Allure::Gpx::ChartSeries.new(points: selected, max_points: @max_points, series: chosen).call
      columns = [ :distance, :elapsed_time, *chosen ]
      columns << :recording_segment if segments.size > 1

      {
        columns:,
        rows: bounded.map { |point| columns.map { cell(point, it) } },
        recorded_series: recorded,
        missing_series: (@requested ? (SERIES & @requested) - recorded : []),
        recording_segments: segments.size,
        points_in_range: selected.size,
        points_returned: bounded.size
      }
    end

    private

    def in_range?(point)
      distance = point[:distance]
      return false if @from_distance && distance < @from_distance
      return false if @to_distance && distance > @to_distance
      return true unless @from_time || @to_time

      elapsed = point[:elapsed_time]
      return false if elapsed.nil?
      return false if @from_time && elapsed < @from_time

      !(@to_time && elapsed > @to_time)
    end

    def cell(point, column)
      column == :recording_segment ? point[:segment_index] : point[column]
    end
  end
end
