# frozen_string_literal: true

module Allure
  module Laps
    # Shared hysteresis engine for effort intervals: enter a block once the
    # smoothed value holds the enter threshold for the minimum duration, leave
    # it once the value drops below the exit threshold for the minimum
    # recovery. A recording gap always ends the block. The engine only returns
    # index ranges; the caller builds the laps.
    class IntervalDetector
      SMOOTHING_SECONDS = 20.0

      def initialize(points:, enter:, exit:, min_duration:, min_recovery:,
                     smoothing_seconds: SMOOTHING_SECONDS, &value_for)
        @points = points
        @enter = enter.to_f
        @exit = exit.to_f
        @min_duration = min_duration.to_f
        @min_recovery = min_recovery.to_f
        @smoothing_seconds = smoothing_seconds.to_f
        @value_for = value_for
      end

      def ranges
        values = smoothed_values
        ranges = []
        pending_start = nil
        pending_duration = 0.0
        active_start = nil
        last_active = nil
        recovery = 0.0

        @points.each_with_index do |point, index|
          next if index.zero?

          previous = @points[index - 1]
          if previous.segment_index != point.segment_index
            ranges << [ active_start, last_active ] if active_start
            pending_start = pending_duration = active_start = last_active = nil
            recovery = 0.0
            next
          end

          duration = point.time - previous.time
          next unless duration.positive?

          value = values[index]
          if value && value >= @enter
            if active_start
              last_active = point.index
              recovery = 0.0
            else
              pending_start ||= previous.index
              pending_duration ||= 0.0
              pending_duration += duration
              if pending_duration >= @min_duration
                active_start = pending_start
                last_active = point.index
                recovery = 0.0
              end
            end
          elsif active_start
            recovery += duration
            if (value.nil? || value < @exit) && recovery >= @min_recovery
              ranges << [ active_start, last_active ]
              active_start = last_active = nil
              recovery = 0.0
            end
          else
            pending_start = nil
            pending_duration = 0.0
          end
        end
        ranges << [ active_start, last_active ] if active_start

        ranges.filter_map { |start, stop| [ start, stop ] if start && stop && stop > start }
      end

      private

      # The mean of the recorded values within ±half the smoothing window of
      # each point, nil where none was recorded. The stream is in recording
      # order, so the window is one sliding range over the whole track rather
      # than a rescan per point: a 50 000-point ultra stays linear.
      def smoothed_values
        return [] if @points.empty?

        values = @points.map { |point| numeric(@value_for.call(point)) }
        return values if @smoothing_seconds <= 0

        half = @smoothing_seconds / 2.0
        times = @points.map(&:time)
        sum = 0.0
        count = 0
        low = 0
        high = 0
        times.each_index.map do |index|
          time = times[index]
          while high < times.length && times[high] - time <= half
            if (value = values[high])
              sum += value
              count += 1
            end
            high += 1
          end
          while low < high && time - times[low] > half
            if (value = values[low])
              sum -= value
              count -= 1
            end
            low += 1
          end
          count.zero? ? nil : sum / count
        end
      end

      def numeric(value)
        value.to_f if value.is_a?(Numeric) && value.finite?
      end
    end
  end
end
