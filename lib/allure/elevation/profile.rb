# frozen_string_literal: true

module Allure
  module Elevation
    # Distance-keyed elevation profile built from provider samples.
    #
    # Only contiguous runs of valid samples are interpolated: a sample the
    # provider could not answer (nil) breaks the profile, so a missing raster
    # never fabricates terrain across the hole. Within a run, values are
    # linearly interpolated on the workout-wide horizontal distance. A distance
    # outside every run has no elevation.
    class Profile
      # Cumulative distances carry float noise; a query a hair away from a
      # sample still reads that sample.
      DISTANCE_EPSILON = 1e-6

      def initialize(samples)
        @runs = []
        @distances = []
        @elevations = []
        run_id = -1
        previous_valid = false

        Array(samples).each do |sample|
          distance = numeric(value(sample, :distance))
          elevation = numeric(value(sample, :elevation))
          valid = !distance.nil? && !elevation.nil?

          unless valid
            previous_valid = false
            next
          end

          run_id += 1 unless previous_valid
          @runs << run_id
          @distances << distance
          @elevations << elevation
          previous_valid = true
        end
      end

      def elevation_at(distance)
        return nil if distance.nil? || @distances.empty?

        value = distance.to_f
        position = lower_bound(value)

        if position >= @distances.length
          return within_epsilon?(@distances.last, value) ? @elevations.last : nil
        end
        return @elevations[position] if within_epsilon?(@distances[position], value)
        return nil if position.zero?
        return nil unless @runs[position - 1] == @runs[position]

        interpolate(position, value)
      end

      private

      def within_epsilon?(sample_distance, distance)
        (sample_distance - distance).abs <= DISTANCE_EPSILON
      end

      def interpolate(position, distance)
        left = position - 1
        span = @distances[position] - @distances[left]
        return @elevations[left] if span.zero?

        ratio = (distance - @distances[left]) / span
        @elevations[left] + ((@elevations[position] - @elevations[left]) * ratio)
      end

      def lower_bound(distance)
        left = 0
        right = @distances.length
        while left < right
          middle = (left + right) / 2
          if @distances[middle] < distance
            left = middle + 1
          else
            right = middle
          end
        end
        left
      end

      def value(sample, key)
        return sample.public_send(key) if sample.respond_to?(key)

        sample[key] || sample[key.to_s]
      end

      def numeric(value)
        return nil unless value.is_a?(Numeric)
        return nil unless value.to_f.finite?

        value.to_f
      end
    end
  end
end
