# frozen_string_literal: true

module Segments
  # Reuses the owner's existing loop segment for a newly detected circuit
  # instead of creating one private loop per workout (docs/dev/SEGMENTS.md).
  # The candidate and the stored geometry must describe the same circuit within
  # the segment's own matching tolerance; a loop the owner renamed is elected
  # first — its name is the identity the owner chose — and otherwise the oldest
  # similar segment wins, so the name and the owner image stay stable. Sport is
  # deliberately ignored: the same canal loop may be recorded as `rowing` and
  # `rowing_virtual`.
  class LoopReuse
    # Detection and reuse generation: also bump when candidate discovery
    # changes, so previously loopless recordings are retried (§4).
    VERSION = 3

    MIN_LENGTH_RATIO = Allure::Segments::Matcher::MIN_LENGTH_RATIO
    MAX_LENGTH_RATIO = Allure::Segments::Matcher::MAX_LENGTH_RATIO
    # One degree of latitude in meters, used only to pad the cheap bounding-box
    # prefilter before the Hausdorff comparison runs.
    METERS_PER_DEGREE = 111_320.0

    def initialize(workout:, candidate:)
      @workout = workout
      @candidate = candidate
    end

    # The oldest similar loop of the owner, or nil.
    def call
      candidates.find { |segment| similar?(segment) }
    end

    private

    def candidates
      @workout.user.segments
        .where(kind: "loop", active: true)
        .where(
          "segments.distance BETWEEN ? AND ?",
          @candidate.travelled_distance_meters * MIN_LENGTH_RATIO,
          @candidate.travelled_distance_meters * MAX_LENGTH_RATIO
        )
        # Renamed loops come first (`renamed_at` ascending keeps the earliest
        # rename ahead; NULL sorts last), then the oldest segment.
        .order(:renamed_at, :id)
        .select { |segment| bounds_overlap?(segment) }
    end

    # The circuit is compared as a set of points: a different start point on
    # the same circuit still measures near zero.
    def similar?(segment)
      Allure::Geometry::Hausdorff.symmetric_distance(
        segment_coordinates(segment),
        @candidate.coordinates
      ) <= segment.match_tolerance_meters
    end

    def bounds_overlap?(segment)
      lat_min, lon_min, lat_max, lon_max = bounds(@candidate.coordinates)
      stored_lat_min, stored_lon_min, stored_lat_max, stored_lon_max = segment.bounds
      pad = segment.match_tolerance_meters / METERS_PER_DEGREE

      lat_min - pad <= stored_lat_max && stored_lat_min <= lat_max + pad &&
        lon_min - pad <= stored_lon_max && stored_lon_min <= lon_max + pad
    end

    def segment_coordinates(segment)
      segment.geom.points.map { |point| [ point.x, point.y ] }
    end

    def bounds(coordinates)
      latitudes = coordinates.map(&:last)
      longitudes = coordinates.map(&:first)
      [ latitudes.min, longitudes.min, latitudes.max, longitudes.max ]
    end
  end
end
