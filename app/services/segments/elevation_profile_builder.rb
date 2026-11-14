# frozen_string_literal: true

module Segments
  # Rebuilds the stored elevation profile of an existing segment from its
  # source workout, for the backfill sweep. Segments created normally already
  # carry their profile; this path exists only for rows created before the
  # column, and it refuses a stale provenance: a re-analysis can replace the
  # source points, in which case the stored indexes no longer designate the
  # course and the builder stores [] instead of a wrong curve.
  class ElevationProfileBuilder
    COORDINATE_TOLERANCE_METERS = 5.0
    DISTANCE_TOLERANCE_RATIO = 0.02
    DISTANCE_TOLERANCE_MINIMUM_METERS = 50.0

    def initialize(segment:)
      @segment = segment
    end

    def call
      return [] unless usable_indexes?

      selected = stream[@segment.source_start_index..@segment.source_end_index]
      return [] unless valid_selection?(selected)

      Allure::Segments::ElevationProfile.dump(selected)
    end

    private

    def source
      @segment.source_workout
    end

    def usable_indexes?
      return false if source.nil?

      start_index = @segment.source_start_index
      end_index = @segment.source_end_index
      start_index.is_a?(Integer) && end_index.is_a?(Integer) &&
        start_index >= 0 && end_index > start_index
    end

    def stream
      @stream ||= Allure::Segments::PointStream.new(
        segments: source.track_segments,
        workout_started_at: source.started_at
      ).call
    end

    def valid_selection?(selected)
      return false unless selected && selected.length >= 2

      endpoints_match?(selected.first, @segment.start_point) &&
        endpoints_match?(selected.last, @segment.end_point) &&
        length_matches?(selected)
    end

    def endpoints_match?(point, geography)
      return false if geography.nil?

      Allure::Gpx::Geo.horizontal_distance(
        point.latitude, point.longitude, geography.y, geography.x
      ) <= COORDINATE_TOLERANCE_METERS
    end

    def length_matches?(selected)
      covered = selected.last.distance - selected.first.distance
      tolerance = [ @segment.distance.to_f * DISTANCE_TOLERANCE_RATIO, DISTANCE_TOLERANCE_MINIMUM_METERS ].max
      (covered - @segment.distance.to_f).abs <= tolerance
    end
  end
end
