# frozen_string_literal: true

module Allure
  module Laps
    # Per-slice metrics for a derived lap, computed from the flattened point
    # stream. Mirrors the moving/stopped rule of Allure::Segments::EffortMetrics
    # so a smart lap and an effort agree on elapsed and moving time.
    class Metrics
      Result = Data.define(
        :started_at,
        :elapsed_time,
        :moving_time,
        :distance,
        :ascent,
        :descent,
        :average_speed,
        :average_pace,
        :max_speed,
        :average_heart_rate,
        :max_heart_rate,
        :average_cadence,
        :average_power,
        :max_power,
        :grade_adjusted_pace
      ) do
        def initialize(started_at:, elapsed_time:, moving_time:, distance:, ascent:, descent:,
                       average_speed:, average_pace:, max_speed:, average_heart_rate:,
                       max_heart_rate:, average_cadence:, average_power:, max_power:,
                       grade_adjusted_pace:)
          super
        end
      end

      def initialize(points:, stopped_speed_threshold_km_h: 0.0, grade_adjusted_pace: false, elevation_filter: nil)
        @points = points
        @stopped_speed_threshold_mps = stopped_speed_threshold_km_h.to_f / 3.6
        @grade_adjusted_pace = grade_adjusted_pace
        @elevation_filter = elevation_filter
      end

      def call
        return if @points.length < 2

        elapsed_time = (@points.last.time - @points.first.time).round
        distance = @points.last.distance - @points.first.distance
        return if elapsed_time <= 0 || distance <= 0

        intervals = @points.each_cons(2).map { |first, second| interval(first, second) }
        moving_time = intervals.sum(0.0) { |value| value[:moving] ? value[:duration] : 0.0 }
                              .round.clamp(0, elapsed_time)
        average_speed = moving_time.positive? ? distance / moving_time : 0.0
        elevations = Allure::Gpx::Elevation.ascent_and_descent(
          @points.map(&:elevation),
          threshold: Allure::Gpx::Elevation.threshold_for(@elevation_filter)
        )
        heart_rates = @points.filter_map { |point| point.heart_rate if point.heart_rate.is_a?(Numeric) && point.heart_rate.positive? }
        cadences = @points.filter_map(&:cadence)
        powers = @points.filter_map(&:power)
        max_speed = intervals.filter_map { |value| value[:speed] if value[:duration].positive? }.max

        gap_result = @grade_adjusted_pace ? Allure::Gpx::GradeAdjustedPace.from_points(@points, stopped_speed_threshold_km_h: @stopped_speed_threshold_km_h) : nil
        grade_adjusted_pace_value = gap_result ? (gap_result[:moving_time] / (gap_result[:grade_adjusted_distance] / 1000.0)).round : nil

        Result.new(
          started_at: @points.first.time,
          elapsed_time:,
          moving_time:,
          distance:,
          ascent: elevations.first,
          descent: elevations.last,
          average_speed:,
          average_pace: average_speed.positive? ? (1_000.0 / average_speed).round : nil,
          max_speed: max_speed&.round(4),
          average_heart_rate: rounded_mean(heart_rates),
          max_heart_rate: heart_rates.max&.round,
          average_cadence: rounded_mean(cadences),
          average_power: rounded_mean(powers),
          max_power: powers.max&.round,
          grade_adjusted_pace: grade_adjusted_pace_value
        )
      end

      private

      def interval(first, second)
        duration = second.time - first.time
        delta = second.distance - first.distance
        speed = duration.positive? ? delta / duration : 0.0
        { duration:, moving: duration.positive? && speed > @stopped_speed_threshold_mps, speed: }
      end

      def rounded_mean(values)
        values.empty? ? nil : (values.sum.to_f / values.length).round
      end
    end
  end
end
