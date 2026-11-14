# frozen_string_literal: true

module Allure
  module Elevation
    # Selects the ordered locations sent to the elevation provider: the first
    # point, then one point every `interval_metres` of workout-wide horizontal
    # distance, plus the final point. Points inside a stationary stretch never
    # advance the distance, so a pause cannot consume the provider budget.
    module Sampler
      Sample = Data.define(:distance, :latitude, :longitude)

      DEFAULT_INTERVAL_METRES = 50.0
      MAX_LOCATIONS = OpenTopoData::MAX_LOCATIONS
      # Cumulative distances carry float noise; a sample exactly on an interval
      # boundary must not be pushed to the next point.
      DISTANCE_EPSILON = 1e-6

      module_function

      def call(segments, interval_metres: DEFAULT_INTERVAL_METRES)
        interval = interval_metres.to_f
        raise ArgumentError, "interval_metres must be positive" unless interval.positive?

        distances = TrackGeometry.cumulative_distances(segments)
        samples = []
        next_distance = nil

        segments.each_with_index do |segment, segment_index|
          segment.points.each_with_index do |point, point_index|
            distance = distances[segment_index][point_index]
            next unless samples.empty? || distance + DISTANCE_EPSILON >= next_distance

            samples << Sample.new(distance:, latitude: point.latitude, longitude: point.longitude)
            next_distance = distance + interval
          end
        end

        append_final(samples, distances, segments)
        samples
      end

      # Splits the samples into provider-sized batches without reordering.
      def chunks(samples, max_locations: MAX_LOCATIONS)
        Array(samples).each_slice(max_locations).to_a
      end

      def append_final(samples, distances, segments)
        index = segments.rindex { |segment| segment.points.any? }
        return unless index

        distance = distances[index].last
        return if samples.any? && samples.last.distance + DISTANCE_EPSILON >= distance

        point = segments[index].points.last
        samples << Sample.new(distance:, latitude: point.latitude, longitude: point.longitude)
      end
    end
  end
end
