# frozen_string_literal: true

module Allure
  module Gpx
    class Splits
      Split = Data.define(:number, :distance, :elapsed_time, :start_time, :end_time, :partial, :ascent, :descent, :average_power, :grade_adjusted_pace) do
        def initialize(number:, distance:, elapsed_time:, start_time:, end_time:, partial:, ascent: 0.0, descent: 0.0,
                       average_power: nil, grade_adjusted_pace: nil)
          super
        end
      end

      INTERVALS = {
        "metric" => Allure::Units::METRES_PER_KILOMETRE,
        "imperial" => Allure::Units::METRES_PER_MILE
      }.freeze
      EPSILON = 1e-9

      # `interval:` (metres) overrides the unit's kilometre or mile, for the
      # REST API's `?distance=` (docs/dev/API.md).
      def initialize(segments:, workout_started_at:, unit: nil, interval: nil, stopped_speed_threshold_km_h: 0.0,
                     grade_adjusted_pace: false, elevation_filter: nil)
        @segments = segments
        @interval = interval&.to_f || INTERVALS.fetch(unit.to_s) { raise ArgumentError, "unknown unit: #{unit.inspect}" }
        raise ArgumentError, "interval must be positive" unless @interval.positive?
        @workout_started_at = workout_started_at
        @stopped_speed_threshold_mps = stopped_speed_threshold_km_h.to_f / 3.6
        @grade_adjusted_pace = grade_adjusted_pace
        @ascent_threshold = Allure::Gpx::Elevation.threshold_for(elevation_filter)
      end

      def call
        points = Allure::Segments::PointStream
          .new(segments: @segments, workout_started_at: @workout_started_at)
          .call
        return [] if points.length < 2

        elevations = points.map(&:elevation)
        start_point = points.first
        split_start_distance = start_point.distance.to_f
        split_start_time = start_point.time
        split_start_index = 0
        next_boundary = split_start_distance + @interval
        splits = []
        ascent = 0.0
        descent = 0.0
        pending = 0.0
        adjusted_distance = 0.0
        moving_time = 0.0

        points.each_cons(2).with_index do |(previous, current), index|
          delta = elevation_delta(elevations, index)
          if delta
            pending += delta
            if pending >= @ascent_threshold
              ascent += pending
              pending = 0.0
            elsif pending <= -@ascent_threshold
              descent += -pending
              pending = 0.0
            end
          else
            pending = 0.0
          end
          next unless current.distance > previous.distance

          duration = current.time - previous.time
          if duration.positive?
            distance_delta = current.distance - previous.distance
            speed = distance_delta / duration
            if @grade_adjusted_pace && speed > @stopped_speed_threshold_mps
              previous_ele = elevations[index]
              current_ele = elevations[index + 1]
              if previous_ele && current_ele
                horizontal = Allure::Gpx::Geo.horizontal_distance(previous.latitude, previous.longitude, current.latitude, current.longitude)
                if horizontal.positive?
                  grade = (current_ele - previous_ele) / horizontal
                  adjusted_distance += distance_delta * Allure::Gpx::GradeAdjustedPace.adjustment_factor(grade)
                  moving_time += duration
                end
              end
            end
          end

          while next_boundary <= current.distance + EPSILON
            fraction = (next_boundary - previous.distance.to_f) /
                       (current.distance.to_f - previous.distance.to_f)
            end_time = interpolate_time(previous.time, current.time, fraction)
            splits << build_split(
              splits.length + 1,
              next_boundary - split_start_distance,
              split_start_time,
              end_time,
              ascent:,
              descent:,
              partial: false,
              power_points: points[split_start_index..index + 1],
              grade_adjusted_pace: grade_adjusted_pace_for(adjusted_distance, moving_time)
            )
            split_start_distance = next_boundary
            split_start_time = end_time
            split_start_index = index + 1
            next_boundary += @interval
            ascent = 0.0
            descent = 0.0
            pending = 0.0
            adjusted_distance = 0.0
            moving_time = 0.0
          end
        end

        final_point = points.last
        remaining_distance = final_point.distance.to_f - split_start_distance
        if remaining_distance > EPSILON
          splits << build_split(
            splits.length + 1,
            remaining_distance,
            split_start_time,
            final_point.time,
            ascent:,
            descent:,
            partial: true,
            power_points: points[split_start_index..],
            grade_adjusted_pace: grade_adjusted_pace_for(adjusted_distance, moving_time)
          )
        end

        splits
      end

      private

      def grade_adjusted_pace_for(adjusted_distance, moving_time)
        return nil unless @grade_adjusted_pace && adjusted_distance.positive? && moving_time.positive?

        (moving_time / (adjusted_distance / 1000.0)).round
      end

      def build_split(number, distance, start_time, end_time, ascent:, descent:, partial:, power_points: [], grade_adjusted_pace: nil)
        Split.new(
          number: number,
          distance: distance,
          elapsed_time: end_time - start_time,
          start_time: start_time,
          end_time: end_time,
          ascent: ascent.round(2),
          descent: descent.round(2),
          partial: partial,
          average_power: mean_power(power_points),
          grade_adjusted_pace: grade_adjusted_pace
        )
      end

      # The same sample mean the recorded and detected laps use, so a split and
      # a lap over the same stretch read the same watts.
      def mean_power(points)
        powers = points.filter_map { |point| point.power if point.power.is_a?(Numeric) }
        return nil if powers.empty?

        (powers.sum.to_f / powers.length).round
      end

      def elevation_delta(elevations, index)
        previous = elevations[index]
        current = elevations[index + 1]
        return unless previous && current

        current - previous
      end

      def interpolate_time(first, second, fraction)
        first + ((second - first) * fraction)
      end
    end
  end
end
