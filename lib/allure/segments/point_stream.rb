# frozen_string_literal: true

module Allure
  module Segments
    class PointStream
      KEYS = Allure::Gpx::PointSerializer

      def initialize(segments:, workout_started_at:)
        @segments = segments
        @workout_started_at = workout_started_at
      end

      def call
        distance_offset = 0.0
        global_index = 0

        ordered_segments.each_with_index.flat_map do |segment, segment_index|
          points = segment.points
          segment_points = points.each_with_index.map do |point, segment_point_index|
            time_offset = point.fetch(KEYS::KEY_TIME)
            time = segment.started_at + time_offset
            value = Point.new(
              index: global_index,
              segment_index: segment_index,
              segment_point_index: segment_point_index,
              time: time,
              elapsed_time: time - @workout_started_at,
              distance: distance_offset + point.fetch(KEYS::KEY_DISTANCE),
              # A positionless recording's points carry no coordinates at all
              # (docs/dev/NO-GPS.md): every distance-driven consumer keeps
              # working, and the coordinate-driven ones see nil.
              longitude: point[KEYS::KEY_LONGITUDE],
              latitude: point[KEYS::KEY_LATITUDE],
              elevation: point[KEYS::KEY_ELEVATION],
              speed: point[KEYS::KEY_SPEED],
              heart_rate: point[KEYS::KEY_HEART_RATE],
              cadence: point[KEYS::KEY_CADENCE],
              power: point[KEYS::KEY_POWER]
            )
            global_index += 1
            value
          end
          distance_offset += segment.distance.to_f
          segment_points
        end
      end

      private

      def ordered_segments
        @segments.to_a.each_with_index
          .sort_by { |segment, index| [ segment_position(segment, index), index ] }
          .map(&:first)
      end

      def segment_position(segment, fallback)
        segment.respond_to?(:position) && !segment.position.nil? ? segment.position : fallback
      end
    end
  end
end
