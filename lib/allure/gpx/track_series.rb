# frozen_string_literal: true

module Allure
  module Gpx
    # The GeoJSON the interactive map consumes.
    #
    # One Feature per recording segment, so a pause never draws a connecting
    # line across a gap, and per-point metrics carried as parallel arrays
    # indexed alongside the coordinates. One Feature per point would express the
    # same information at several times the size.
    #
    # Distances are workout-cumulative, exactly as `ChartSeries` reports them.
    # The map and the chart are synchronised by distance, so if these two ever
    # disagreed the map would quietly highlight the wrong place rather than fail
    # visibly. `spec/lib/allure/gpx/track_series_spec.rb` pins that agreement.
    #
    # Elapsed time is deliberately absent: the chart payload already carries it,
    # and on the largest real track measured here it cost 30 KB gzipped to
    # repeat.
    class TrackSeries
      # Metrics a client can colour a track by. A metric absent from every point
      # is omitted entirely rather than sent as an array of nulls.
      METRICS = {
        elevation: PointSerializer::KEY_ELEVATION,
        speed: PointSerializer::KEY_SPEED,
        power: PointSerializer::KEY_POWER
      }.freeze

      def initialize(segments:)
        @segments = segments
      end

      def call
        { type: "FeatureCollection", features: features }
      end

      private

      def features
        distance_offset = 0.0

        @segments.each_with_index.map do |segment, segment_index|
          feature = feature_for(segment, segment_index, distance_offset)
          distance_offset += segment.distance.to_f
          feature
        end
      end

      def feature_for(segment, segment_index, distance_offset)
        points = segment.points

        {
          type: "Feature",
          geometry: { type: "LineString", coordinates: coordinates(points) },
          properties: properties(points, segment_index, distance_offset)
        }
      end

      # GeoJSON axis order. The repository keeps [longitude, latitude]
      # everywhere; only the map library's own call boundary may reorder it.
      def coordinates(points)
        points.map do
          [ it.fetch(PointSerializer::KEY_LONGITUDE), it.fetch(PointSerializer::KEY_LATITUDE) ]
        end
      end

      def properties(points, segment_index, distance_offset)
        result = {
          segment_index:,
          distance: points.map { (distance_offset + it.fetch(PointSerializer::KEY_DISTANCE)).round(1) }
        }

        METRICS.each do |name, key|
          values = points.map { it[key] }
          result[name] = values if values.any? { !it.nil? }
        end

        result
      end
    end
  end
end
