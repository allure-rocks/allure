# frozen_string_literal: true

module Api
  module Rest
    module V1
      # The owner's recorded track as GeoJSON (PLAN_API.md §6.2): one LineString
      # Feature per recording segment, never joined across a pause, with the
      # per-point measurements as parallel arrays. A measurement absent from
      # every point of a segment is omitted for that segment.
      class TrackSerializer
        KEY = Allure::Gpx::PointSerializer
        SERIES = {
          elevations: KEY::KEY_ELEVATION,
          speeds: KEY::KEY_SPEED,
          heart_rates: KEY::KEY_HEART_RATE,
          cadences: KEY::KEY_CADENCE,
          powers: KEY::KEY_POWER
        }.freeze

        def initialize(workout)
          @workout = workout
        end

        def as_json(*)
          offset = 0.0
          features = @workout.track_segments.map do |segment|
            feature = feature_for(segment, offset)
            offset += segment.distance.to_f
            feature
          end
          { type: "FeatureCollection", features: }
        end

        private

        def feature_for(segment, offset)
          points = Array(segment.points)
          properties = {
            segment_index: segment.position,
            started_at: Formats.time(segment.started_at),
            times: points.map { it[KEY::KEY_TIME] },
            distances: points.map { (offset + it[KEY::KEY_DISTANCE].to_f).round(1) }
          }
          SERIES.each do |name, key|
            values = points.map { it[key] }
            properties[name] = values if values.any? { !it.nil? }
          end
          # Two-dimensional positions: elevation is a parallel series, since a
          # LineString's positions must all have the same dimension.
          coordinates = points.map { [ it[KEY::KEY_LONGITUDE], it[KEY::KEY_LATITUDE] ] }
          { type: "Feature", geometry: { type: "LineString", coordinates: }, properties: }
        end
      end
    end
  end
end
