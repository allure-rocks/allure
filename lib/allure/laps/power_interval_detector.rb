# frozen_string_literal: true

module Allure
  module Laps
    # Sustained power blocks for sports that record power. Missing samples and
    # zeros (coasting) both pull the smoothed series down, so a sensor dropout
    # ends a block instead of faking a longer effort.
    class PowerIntervalDetector
      include IntervalLapBuilder

      MIN_VALUES = 60

      def initialize(points:, colour_group:, stopped_speed_threshold_km_h: 0.0, grade_adjusted_pace: false)
        @points = points
        @profile = Allure::Laps::Profiles.power(colour_group)
        @stopped_speed_threshold_km_h = stopped_speed_threshold_km_h
        @grade_adjusted_pace = grade_adjusted_pace
      end

      def call
        return [] if @points.length < 4 || @profile.nil?

        powers = {}
        @points.each do |point|
          powers[point.index] = point.power if point.power.is_a?(Numeric) && point.power >= 0
        end
        positive = powers.values.select(&:positive?)
        return [] if positive.length < MIN_VALUES

        enter = [ @profile.enter, Allure::Laps::Profiles.percentile(positive, 0.85) ].compact.max
        exit = [ @profile.exit, Allure::Laps::Profiles.percentile(positive, 0.70), enter * 0.75 ].compact.max
        exit = enter * 0.8 if exit >= enter

        Allure::Laps::IntervalDetector.new(
          points: @points,
          enter:,
          exit:,
          min_duration: @profile.min_duration,
          min_recovery: @profile.min_recovery
        ) { |point| powers[point.index] }
          .ranges
          .filter_map { |start, stop| build_interval_lap("power_interval", start, stop) }
      end
    end
  end
end
