# frozen_string_literal: true

module Allure
  module Gpx
    # Grade Adjusted Pace (GAP): the flat-equivalent pace accounting for
    # terrain gradient. Pure Ruby, framework-independent, and fully
    # deterministic.
    #
    # Uphill uses the Minetti 2002 energy-cost polynomial; downhill uses a
    # Descent cost curve (minimum ≈ 0.88 around −9 %, back to 1.0 by
    # −18 %, no further benefit beyond) so that steep descents are not
    # over-credited, unlike the raw laboratory model.
    #
    # See docs/dev/WORKOUT.md for the locked contract.
    module GradeAdjustedPace
      MINETTI_COEFFICIENTS = [ 155.4, -30.4, -43.3, 46.3, 19.5, 3.6 ].freeze
      FLAT_COST = 3.6
      MAX_UPHILL_GRADE = 0.45
      DESCENT_MINIMUM_FACTOR = 0.88
      DESCENT_MINIMUM_GRADE = -0.09
      DESCENT_NEUTRAL_GRADE = -0.18

      module_function

      # Returns the adjustment factor for a given gradient (decimal fraction).
      # factor = 1.0 means flat-equivalent; < 1.0 uphill (faster GAP).
      def adjustment_factor(grade)
        g = [ [ grade, -MAX_UPHILL_GRADE ].max, MAX_UPHILL_GRADE ].min
        if g >= 0
          minetti_cost(g) / FLAT_COST
        else
          descent_factor(grade)
        end
      end

      # Computes the grade-adjusted distance (metres) and moving time (seconds)
      # from a flat list of points. Points must respond to `time`, `longitude`,
      # `latitude`, and `elevation`, and their elevations must already be the
      # canonical filtered profile (docs/dev/WORKOUT.md): this method never
      # smooths again. The distance basis mirrors `Geo.distance` (3D when both
      # endpoints carry an elevation, horizontal otherwise), and only moving
      # intervals whose endpoints share a valid elevation contribute. Returns
      # +nil+ when no eligible interval exists.
      def from_points(points, stopped_speed_threshold_km_h:)
        return nil if points.length < 2

        threshold_mps = stopped_speed_threshold_km_h.to_f / 3.6
        elevations = points.map(&:elevation)
        adjusted_distance = 0.0
        moving_time = 0.0

        points.each_cons(2).with_index do |(previous, current), index|
          next unless current.time && previous.time

          duration = current.time - previous.time
          next unless duration.positive?

          # A positionless recording (docs/dev/NO-GPS.md) has no gradient at
          # all: its unpositioned points are skipped here, so a positionless
          # track answers +nil+ — the documented "no eligible interval"
          # contract — instead of crashing on nil coordinates.
          next if previous.latitude.nil? || previous.longitude.nil? ||
                  current.latitude.nil? || current.longitude.nil?

          horizontal = Allure::Gpx::Geo.horizontal_distance(
            previous.latitude, previous.longitude,
            current.latitude, current.longitude
          )
          next unless horizontal.positive?

          distance = interval_distance(previous, current, horizontal)
          speed = distance / duration
          next unless speed > threshold_mps

          previous_ele = elevations[index]
          current_ele = elevations[index + 1]
          next unless previous_ele && current_ele

          grade = (current_ele - previous_ele) / horizontal
          adjusted_distance += distance * adjustment_factor(grade)
          moving_time += duration
        end

        return nil if adjusted_distance <= 0 || moving_time <= 0

        { grade_adjusted_distance: adjusted_distance, moving_time: moving_time }
      end

      # Returns the grade-adjusted pace in seconds per kilometre, or +nil+.
      def grade_adjusted_pace(points, stopped_speed_threshold_km_h:)
        result = from_points(points, stopped_speed_threshold_km_h:)
        return nil unless result

        (result[:moving_time] / (result[:grade_adjusted_distance] / 1000.0)).round
      end

      def minetti_cost(g)
        MINETTI_COEFFICIENTS.inject(0) { |acc, c| acc * g + c }
      end

      def interval_distance(previous, current, horizontal)
        return horizontal if previous.elevation.nil? || current.elevation.nil?

        elevation_delta = current.elevation - previous.elevation
        Math.sqrt((horizontal**2) + (elevation_delta**2))
      end

      def descent_factor(grade)
        return 1.0 if grade < DESCENT_NEUTRAL_GRADE
        return 1.0 if grade >= 0

        distance_from_minimum = ((grade - DESCENT_MINIMUM_GRADE) / DESCENT_MINIMUM_GRADE) ** 2
        1.0 - (1.0 - DESCENT_MINIMUM_FACTOR) * (1.0 - distance_from_minimum)
      end
    end
  end
end
