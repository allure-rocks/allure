# frozen_string_literal: true

module Allure
  module Laps
    # A stop is a run of near-zero speed inside one recording segment. Speed is
    # derived from distance and time deltas, never from the optional point
    # speed field, and a recording gap splits or discards the block. The
    # sport's stopped-speed threshold decides where a stop starts; a short exit
    # window confirms where it ends.
    class StopDetector
      MIN_DURATION_SECONDS = 30
      EXIT_SECONDS = 5
      FALLBACK_THRESHOLD_MPS = 0.5

      def initialize(points:, stopped_speed_threshold_km_h: 0.0, elevation_filter: nil)
        @points = points
        threshold = stopped_speed_threshold_km_h.to_f / 3.6
        @threshold_mps = threshold.positive? ? threshold : FALLBACK_THRESHOLD_MPS
        @elevation_filter = elevation_filter
      end

      def call
        stops = []
        start_index = nil
        last_slow_index = nil
        exit_duration = 0.0

        @points.each_cons(2) do |first, second|
          if first.segment_index != second.segment_index
            stops << build(start_index, last_slow_index)
            start_index = last_slow_index = nil
            exit_duration = 0.0
            next
          end

          duration = second.time - first.time
          next unless duration.positive?

          speed = (second.distance - first.distance) / duration
          if speed <= @threshold_mps
            start_index ||= first.index
            last_slow_index = second.index
            exit_duration = 0.0
          elsif start_index
            exit_duration += duration
            if exit_duration >= EXIT_SECONDS
              stops << build(start_index, last_slow_index)
              start_index = last_slow_index = nil
              exit_duration = 0.0
            end
          end
        end
        stops << build(start_index, last_slow_index)
        stops.compact
      end

      private

      def build(start_index, end_index)
        return if start_index.nil? || end_index.nil? || end_index <= start_index

        slice = @points[start_index..end_index]
        elapsed_time = (slice.last.time - slice.first.time).round
        return if elapsed_time < MIN_DURATION_SECONDS

        ascent, descent = Allure::Gpx::Elevation.ascent_and_descent(
          slice.map(&:elevation),
          threshold: Allure::Gpx::Elevation.threshold_for(@elevation_filter)
        )
        heart_rates = slice.filter_map { |point| point.heart_rate if point.heart_rate.is_a?(Numeric) && point.heart_rate.positive? }
        cadences = slice.filter_map(&:cadence)
        powers = slice.filter_map(&:power)

        Allure::Laps::Lap.new(
          source: "stop",
          start_point_index: start_index,
          end_point_index: end_index,
          start_distance: slice.first.distance.to_f,
          end_distance: slice.last.distance.to_f,
          started_at: slice.first.time,
          elapsed_time:,
          moving_time: 0,
          distance: [ slice.last.distance.to_f - slice.first.distance.to_f, 0.0 ].max,
          ascent:,
          descent:,
          average_speed: 0.0,
          average_heart_rate: mean(heart_rates),
          max_heart_rate: heart_rates.max&.round,
          average_cadence: mean(cadences),
          average_power: mean(powers),
          max_power: powers.max&.round
        )
      end

      def mean(values)
        values.empty? ? nil : (values.sum.to_f / values.length).round
      end
    end
  end
end
