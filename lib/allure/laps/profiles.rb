# frozen_string_literal: true

module Allure
  module Laps
    # Starting thresholds for the interval detectors, keyed by the sport's
    # `colour_group`. Group floors are absolute; the workout percentile only
    # raises them, so a slow workout never invents sprints and a fast one is
    # not capped below its own level.
    module Profiles
      Speed = Data.define(:enter, :exit, :min_duration, :min_recovery) do
        def initialize(enter:, exit:, min_duration:, min_recovery:)
          super
        end
      end

      Power = Data.define(:enter, :exit, :min_duration, :min_recovery) do
        def initialize(enter:, exit:, min_duration:, min_recovery:)
          super
        end
      end

      GROUPS = {
        "run" => {
          speed: Speed.new(enter: 3.0, exit: 2.2, min_duration: 20, min_recovery: 10),
          power: Power.new(enter: 220.0, exit: 170.0, min_duration: 60, min_recovery: 30)
        },
        "ride" => {
          speed: Speed.new(enter: 7.5, exit: 5.5, min_duration: 20, min_recovery: 10),
          power: Power.new(enter: 200.0, exit: 150.0, min_duration: 60, min_recovery: 30)
        },
        "hike" => {
          speed: Speed.new(enter: 2.0, exit: 1.4, min_duration: 20, min_recovery: 10)
        },
        "swim" => {
          speed: Speed.new(enter: 1.0, exit: 0.7, min_duration: 20, min_recovery: 10)
        },
        "ski" => {
          speed: Speed.new(enter: 4.5, exit: 3.0, min_duration: 20, min_recovery: 10)
        },
        "other" => {
          speed: Speed.new(enter: 2.5, exit: 1.8, min_duration: 20, min_recovery: 10)
        }
      }.freeze

      module_function

      def speed(colour_group)
        group(colour_group).fetch(:speed)
      end

      def power(colour_group)
        group(colour_group)[:power]
      end

      def percentile(values, fraction)
        sorted = values.sort
        return if sorted.empty?

        sorted[(fraction * (sorted.length - 1)).round]
      end

      def group(colour_group)
        GROUPS.fetch(colour_group.to_s, GROUPS.fetch("other"))
      end
    end
  end
end
