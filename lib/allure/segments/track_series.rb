# frozen_string_literal: true

module Allure
  module Segments
    # The GeoJSON the interactive segment map consumes: one Feature, one
    # LineString, and the cumulative distance at each vertex, so the map and the
    # stored profile synchronise by distance exactly like a workout's track and
    # chart. There is no per-point metric to colour a course by.
    class TrackSeries
      def initialize(coordinates:, distance:)
        @coordinates = coordinates
        @distance = distance.to_f
      end

      def call
        { type: "FeatureCollection", features: [ feature ] }
      end

      private

      def feature
        {
          type: "Feature",
          geometry: { type: "LineString", coordinates: @coordinates },
          properties: { segment_index: 0, distance: distances }
        }
      end

      # The geometry is 2D while the stored segment distance comes from the
      # source's profile; scaling the horizontal run to the stored total keeps
      # both ends aligned, so a hover at the profile's end still finds the
      # finish.
      def distances
        cumulative = 0.0
        raw = @coordinates.map.with_index do |coordinate, index|
          if index.positive?
            previous = @coordinates[index - 1]
            cumulative += Allure::Gpx::Geo.horizontal_distance(
              previous[1], previous[0], coordinate[1], coordinate[0]
            )
          end
          cumulative
        end
        factor = raw.last.positive? && @distance.positive? ? @distance / raw.last : 1.0
        raw.map { (it * factor).round(1) }
      end
    end
  end
end
