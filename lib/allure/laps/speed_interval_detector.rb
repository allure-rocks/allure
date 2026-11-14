# frozen_string_literal: true

module Allure
  module Laps
    # Sustained fast blocks from the derived speed series. The absolute group
    # floor is raised by the workout's own p85 so a slow session invents no
    # sprints; a 20 s smoothing pass keeps GPS spikes from opening a block.
    class SpeedIntervalDetector
      include IntervalLapBuilder

      MIN_MOVING_VALUES = 30

      def initialize(points:, colour_group:, stopped_speed_threshold_km_h: 0.0, grade_adjusted_pace: false)
        @points = points
        @profile = Allure::Laps::Profiles.speed(colour_group)
        @stopped_speed_threshold_km_h = stopped_speed_threshold_km_h
        @stopped_speed_threshold_mps = stopped_speed_threshold_km_h.to_f / 3.6
        @grade_adjusted_pace = grade_adjusted_pace
      end

      def call
        return [] if @points.length < 4

        speeds = interval_speeds
        moving = speeds.compact.select { |speed| speed > @stopped_speed_threshold_mps }
        return [] if moving.length < MIN_MOVING_VALUES

        enter = [ @profile.enter, Allure::Laps::Profiles.percentile(moving, 0.85) ].compact.max
        exit = [ @profile.exit, Allure::Laps::Profiles.percentile(moving, 0.70), enter * 0.75 ].compact.max
        exit = enter * 0.8 if exit >= enter

        by_index = {}
        @points.each_with_index { |point, index| by_index[point.index] = speeds[index] }
        Allure::Laps::IntervalDetector.new(
          points: @points,
          enter:,
          exit:,
          min_duration: @profile.min_duration,
          min_recovery: @profile.min_recovery
        ) { |point| by_index[point.index] }
          .ranges
          .filter_map { |start, stop| build_interval_lap("speed_interval", start, stop) }
      end

      private

      def interval_speeds
        speeds = Array.new(@points.length)
        @points.each_cons(2).with_index do |(first, second), index|
          next if first.segment_index != second.segment_index

          duration = second.time - first.time
          next unless duration.positive?

          speeds[index + 1] = (second.distance - first.distance) / duration
        end
        speeds[0] = speeds[1]
        speeds
      end
    end
  end
end
