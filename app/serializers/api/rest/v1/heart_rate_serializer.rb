# frozen_string_literal: true

module Api
  module Rest
    module V1
      # Heart-rate analysis in the API (docs/dev/HEART-RATE.md). Owner-only
      # by construction: only the token's own workouts and account reach it.
      module HeartRateSerializer
        module_function

        # nil without a usable histogram; zones and load nil without a profile.
        def workout(workout)
          row = workout.recording? ? workout.heart_rate : nil
          return nil unless row&.usable?

          zones = workout.user.heart_rate_zones
          {
            coverage: row.coverage.round(3),
            sampled_seconds: row.sampled_seconds,
            recorded_seconds: row.recorded_seconds,
            covered_seconds: row.covered_seconds,
            frozen_seconds: row.frozen_seconds,
            load: zones ? row.load_for(zones) : nil,
            load_floor_bpm: zones&.load_floor,
            zones: zones ? zone_list(zones, row.zone_seconds_for(zones)) : nil
          }
        end

        def profile(user)
          zones = user.heart_rate_zones
          return nil unless zones

          {
            max: user.max_heart_rate,
            rest: user.resting_heart_rate,
            basis: user.heart_rate_zone_basis,
            bounds: user.heart_rate_zone_bounds,
            thresholds_bpm: zones.thresholds
          }
        end

        def zone_list(zones, seconds)
          zones.ranges.each_with_index.map do |(lower, upper), index|
            { zone: index + 1, lower_bpm: lower, upper_bpm: upper, seconds: seconds.fetch(index) }
          end
        end
      end
    end
  end
end
