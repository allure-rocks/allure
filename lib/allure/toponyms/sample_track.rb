# frozen_string_literal: true

module Allure
  module Toponyms
    # Selects dense representative positions from an immutable track. Base
    # samples are spaced by 100 metres so short settlement passages are not
    # missed; high points and detected climbs are retained as additional roles.
    class SampleTrack
      SAMPLE_INTERVAL_METRES = 100.0
      MIN_INTERVAL_METRES = 1_000.0
      ELEVATION_SAMPLES = 4

      def initialize(segments:)
        @segments = segments
      end

      def call
        points = flatten
        return [] if points.empty?

        total_distance = points.last.fetch(:distance)
        selected = sample_by_distance(points, total_distance)
        selected.concat(segment_boundary_samples(points))
        selected.concat(elevation_samples(points, total_distance))
        selected.concat(climb_samples(points))
        selected.concat([ points.first.merge(role: "start"), points.last.merge(role: "finish") ])

        dedupe(selected)
      end

      private

      def climb_samples(points)
        Allure::Climbs::Segmenter.new(points:, profile: Allure::Climbs::Segmenter::LAP)
          .call.map do |climb|
            original = points.min_by { |point| (point.fetch(:distance) - climb.end_distance).abs }
            original.merge(
              role: "climb_summit",
              climb_gain: climb.gain.round(1),
              climb_prominence: climb.prominence.round(1)
            )
          end
      end

      def flatten
        distance_offset = 0.0

        @segments.flat_map do |segment|
          points = Array(segment.points).filter_map do |point|
            latitude = numeric(point, "lat", :latitude)
            longitude = numeric(point, "lon", :longitude)
            distance = numeric(point, "d", :distance)
            next unless latitude && longitude && distance

            {
              latitude:,
              longitude:,
              distance: (distance_offset + distance).round(1),
              elevation: numeric(point, "ele", :elevation),
              role: "route"
            }
          end
          distance_offset += segment.distance.to_f
          points.each_with_index.map do |point, index|
            point.merge(segment_boundary: index.zero? || index == points.length - 1)
          end
        end.sort_by { it.fetch(:distance) }
      end

      def sample_by_distance(points, total_distance)
        targets = []
        distance = 0.0
        while distance < total_distance
          targets << distance
          distance += SAMPLE_INTERVAL_METRES
        end
        targets << total_distance if targets.empty? || targets.last < total_distance

        nearest_to_targets(points, targets).map { it.merge(role: "route") }
      end

      def segment_boundary_samples(points)
        points.select { it[:segment_boundary] }.map { it.merge(role: "segment_boundary") }
      end

      def elevation_samples(points, total_distance)
        elevated = points.select { it[:elevation] }
        return [] if elevated.empty?

        spacing = [ total_distance * 0.08, MIN_INTERVAL_METRES ].max
        selected = []
        elevated.sort_by { [ -it.fetch(:elevation), it.fetch(:distance) ] }.each do |point|
          next if selected.any? { (it.fetch(:distance) - point.fetch(:distance)).abs < spacing }

          selected << point.merge(role: "high_point")
          break if selected.length >= ELEVATION_SAMPLES
        end
        selected
      end

      def nearest_to_targets(points, targets)
        cursor = 0
        targets.map do |target|
          cursor += 1 while cursor + 1 < points.length &&
            (points[cursor + 1].fetch(:distance) - target).abs <= (points[cursor].fetch(:distance) - target).abs
          points[cursor]
        end
      end

      def dedupe(points)
        roles = {
          "start" => 0,
          "finish" => 0,
          "climb_summit" => 1,
          "high_point" => 2,
          "segment_boundary" => 3,
          "route" => 4
        }
        points
          .group_by { it.fetch(:distance) }
          .values
          .map { it.min_by { |point| roles.fetch(point.fetch(:role)) } }
          .sort_by { it.fetch(:distance) }
      end

      def numeric(point, string_key, symbol_key)
        return nil unless point.is_a?(Hash)

        value = point[string_key].nil? ? point[symbol_key] : point[string_key]
        value.to_f if value.is_a?(Numeric) && value.to_f.finite?
      end
    end
  end
end
