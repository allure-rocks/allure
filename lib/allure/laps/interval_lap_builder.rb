# frozen_string_literal: true

module Allure
  module Laps
    module IntervalLapBuilder
      private

      attr_writer :grade_adjusted_pace

      def build_interval_lap(source, start_index, end_index)
        metrics = Allure::Laps::Metrics.new(
          points: @points[start_index..end_index],
          stopped_speed_threshold_km_h: @stopped_speed_threshold_km_h,
          grade_adjusted_pace: @grade_adjusted_pace
        ).call
        return unless metrics

        Allure::Laps::Lap.new(
          source:,
          start_point_index: start_index,
          end_point_index: end_index,
          start_distance: @points[start_index].distance,
          end_distance: @points[end_index].distance,
          started_at: metrics.started_at,
          elapsed_time: metrics.elapsed_time,
          moving_time: metrics.moving_time,
          distance: metrics.distance,
          ascent: metrics.ascent,
          descent: metrics.descent,
          average_speed: metrics.average_speed,
          average_pace: metrics.average_pace,
          max_speed: metrics.max_speed,
          average_heart_rate: metrics.average_heart_rate,
          max_heart_rate: metrics.max_heart_rate,
           average_cadence: metrics.average_cadence,
           average_power: metrics.average_power,
           max_power: metrics.max_power,
           grade_adjusted_pace: metrics.grade_adjusted_pace
         )
      end
    end
  end
end
