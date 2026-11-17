# frozen_string_literal: true

module Segments
  # The discover map's viewport read (docs/dev/SEGMENTS.md): every course the
  # viewer may see — the readable shared ones and their own, private ones
  # included — whose geometry intersects the requested bounding box. Bounded by
  # a feature cap so a world view can never stream the whole library, and
  # simplified with a tolerance that follows the viewport span so a long course
  # stays one light feature.
  #
  # The read never loads the geometry column itself: it selects the simplified
  # GeoJSON, so the row exists only as a map payload.
  #
  # The cap keeps the courses with the most athletes (the stored counter, never
  # shown); the participants each feature carries are the ones the viewer sees
  # ranked, so an unpublished effort never shows through the map.
  class DiscoveryQuery
    MAX_FEATURES = 200
    # ~11 m at the equator: the floor under which simplification would start
    # deforming a course at street scale.
    MIN_SIMPLIFY_DEGREES = 0.0001
    # At most one kept point every 2000th of the viewport span, so the whole
    # payload stays bounded however far out the reader zooms.
    SIMPLIFY_SPAN_DIVISOR = 2_000

    Row = Data.define(:uuid, :name, :sport, :distance, :participants_count, :geometry)

    def initialize(viewer:, bbox:)
      @viewer = viewer
      @bbox = bbox
    end

    def call
      segments = scope
        .includes(:sport)
        .order(athletes_count: :desc, id: :desc)
        .limit(MAX_FEATURES)
        .select(
          "segments.id", "segments.uuid", "segments.name", "segments.distance",
          "segments.sport_id", "segments.visibility",
          "ST_AsGeoJSON(ST_SimplifyPreserveTopology(segments.geom::geometry, #{simplify_tolerance})) AS simplified_geometry"
        )
        .to_a
      counts = participants_counts(segments)

      segments.map do |segment|
        Row.new(
          uuid: segment.uuid,
          name: segment.name,
          sport: segment.sport,
          distance: segment.distance.to_f,
          participants_count: counts.fetch(segment.id, 0),
          geometry: JSON.parse(segment.simplified_geometry)
        )
      end
    end

    private

    # A shared course counts its board for this viewer; the viewer's own
    # private courses, which have no board, count their efforts.
    def participants_counts(segments)
      private_ids, shared_ids = segments.partition { |segment| segment.visibility == "private" }.map { |group| group.map(&:id) }
      private_counts = private_ids.any? ? private_participants_counts(private_ids) : {}
      Segments::Listing.participants_counts(shared_ids, viewer: @viewer).merge(private_counts)
    end

    def private_participants_counts(segment_ids)
      SegmentEffort
        .where(segment_id: segment_ids)
        .joins(:workout).merge(Workout.recordings)
        .group(:segment_id)
        .distinct
        .count("segment_efforts.user_id")
    end

    def scope
      Segment
        .visible_to(@viewer)
        .where(kind: "segment", active: true)
        .where(
          "segments.geom && ST_MakeEnvelope(?, ?, ?, ?, 4326)::geography",
          @bbox[0], @bbox[1], @bbox[2], @bbox[3]
        )
    end

    def simplify_tolerance
      span = [ @bbox[2] - @bbox[0], @bbox[3] - @bbox[1] ].max
      [ MIN_SIMPLIFY_DEGREES, span / SIMPLIFY_SPAN_DIVISOR ].max
    end
  end
end
