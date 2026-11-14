# frozen_string_literal: true

module Allure
  module Laps
    # One lap per recording segment once the workout was paused at least once.
    # A single uninterrupted recording is not lapped, so a one-segment workout
    # yields no pause laps. Metrics come straight from the stored
    # `track_segments` row; no re-analysis.
    class PauseDetector
      def initialize(segments:)
        @segments = segments
      end

      def call
        segments = @segments.to_a
        return [] if segments.length < 2

        index_offset = 0
        distance_offset = 0.0
        laps = []
        segments.each do |segment|
          lap = build(segment, index_offset, distance_offset)
          laps << lap if lap
          index_offset += Array(segment.points).length
          distance_offset += segment.distance.to_f
        end
        laps
      end

      private

      def build(segment, index_offset, distance_offset)
        points_count = Array(segment.points).length
        duration = segment.duration.to_i
        distance = segment.distance.to_f
        return if points_count < 2 || duration <= 0 || distance <= 0

        Allure::Laps::Lap.new(
          source: "pause",
          start_point_index: index_offset,
          end_point_index: index_offset + points_count - 1,
          start_distance: distance_offset,
          end_distance: distance_offset + distance,
          started_at: segment.started_at,
          elapsed_time: duration,
          moving_time: segment.moving_time.to_i.clamp(0, duration),
          distance:,
          ascent: segment.ascent,
          descent: segment.descent,
          average_speed: segment.average_speed,
          average_pace: segment.average_pace,
          max_speed: segment.max_speed,
          average_heart_rate: segment.average_heart_rate,
          max_heart_rate: segment.max_heart_rate,
          average_cadence: segment.average_cadence,
          average_power: segment.average_power,
          max_power: segment.max_power,
          grade_adjusted_pace: segment.grade_adjusted_pace
        )
      end
    end
  end
end
