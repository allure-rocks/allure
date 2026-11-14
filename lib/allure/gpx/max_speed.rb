# frozen_string_literal: true

module Allure
  module Gpx
    # Selects the fastest speed sustained over a time window. A literal
    # point-to-point maximum is too sensitive to GPS jitter, while a percentile
    # of an entire activity discards genuine short descents and sprints. Ten
    # seconds dilutes a one-sample cold-fix artifact that a three-second window
    # would still report as an impossible speed.
    module MaxSpeed
      WINDOW_SECONDS = 10.0

      module_function

      # Intervals respond to distance, duration, and speed. Windows end at
      # recorded point boundaries; the oldest overlapping interval is prorated
      # so irregular smart-recording intervals remain time-weighted.
      def calculate(intervals)
        intervals = intervals.select { |interval| interval.duration.positive? }
        return nil if intervals.empty? || intervals.none? { |interval| interval.distance.positive? }

        left = 0
        window_distance = 0.0
        window_duration = 0.0
        maximum = nil

        intervals.each do |interval|
          window_distance += interval.distance
          window_duration += interval.duration

          while window_duration - intervals[left].duration >= WINDOW_SECONDS
            window_distance -= intervals[left].distance
            window_duration -= intervals[left].duration
            left += 1
          end

          next if window_duration < WINDOW_SECONDS

          excess_duration = window_duration - WINDOW_SECONDS
          distance = window_distance - (intervals[left].speed * excess_duration)
          speed = distance / WINDOW_SECONDS
          maximum = speed if maximum.nil? || speed > maximum
        end

        maximum || intervals.sum(&:distance) / intervals.sum(&:duration)
      end
    end
  end
end
