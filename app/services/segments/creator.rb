# frozen_string_literal: true

module Segments
  class Creator
    DEFAULT_MATCH_TOLERANCE_METERS = 25
    # A route is a whole track: its endpoints carry the recording's start and
    # stop artefacts, and a consumer GPS drifts more at the ends than inside a
    # segment. Routes therefore default to the top of the allowed range, while
    # segments, detected loops and received courses keep the segment default
    # (docs/dev/SEGMENTS.md).
    ROUTE_MATCH_TOLERANCE_METERS = 100
    # Omitting `sport:` inherits the source workout's sport; passing `nil`
    # creates a segment any sport can match.
    INHERIT_SPORT = :inherit
    # Omitting `match_tolerance_meters:` picks the kind's default: a route's
    # whole-track tolerance or the segment's.
    INHERIT_TOLERANCE = :inherit_tolerance

    def initialize(user:, workout:, name:, description: nil, kind: "segment", start_index: nil, end_index: nil,
                   match_tolerance_meters: INHERIT_TOLERANCE, sport: INHERIT_SPORT,
                   visibility: nil, zone_acknowledged: false)
      @user = user
      @workout = workout
      @name = name
      @description = description
      @kind = kind
      @start_index = integer_or_nil(start_index)
      @end_index = integer_or_nil(end_index)
      @match_tolerance_meters = resolve_tolerance(match_tolerance_meters)
      @sport = sport
      @visibility = visibility.presence
      @zone_acknowledged = zone_acknowledged
    end

    def call
      points = point_stream
      @start_index, @end_index = resolve_indexes(points)
      segment = @user.segments.build(base_attributes)

      unless valid_selection?(points)
        segment.errors.add(:base, :invalid_selection)
        return segment
      end

      segment.assign_attributes(derived_attributes(points))
      segment.save
      segment
    end

    private

    def point_stream
      Allure::Segments::PointStream.new(
        segments: @workout.track_segments,
        workout_started_at: @workout.started_at
      ).call
    end

    def route?
      @kind == "route"
    end

    # A derived segment (route, loop) keeps its source workout's sport unless
    # the caller chose one explicitly; `nil` means every sport is eligible.
    def resolved_sport
      @sport == INHERIT_SPORT ? @workout.sport : @sport
    end

    # A route is the whole track, so the selection spans the entire stream. The
    # indexes are resolved here rather than required from the caller.
    def resolve_indexes(points)
      return [ @start_index, @end_index ] unless route?
      return [ nil, nil ] if points.length < 2

      [ 0, points.length - 1 ]
    end

    def base_attributes
      {
        sport: resolved_sport,
        kind: @kind,
        name: @name,
        description: @description,
        match_tolerance_meters: @match_tolerance_meters,
        visibility: resolved_visibility,
        privacy_zone_acknowledged_at: (@zone_acknowledged ? Time.current : nil),
        active: true,
        matcher_version: Allure::Segments::Matcher::VERSION,
        source_workout: @workout,
        source_start_index: @start_index,
        source_end_index: @end_index
      }
    end

    # Only reusable segments can be shared; routes and loops stay private. An
    # unknown value is preserved so the model's inclusion validation rejects it
    # rather than silently falling back.
    def resolved_visibility
      return "private" unless @kind == "segment"

      @visibility.presence || "private"
    end

    def valid_selection?(points)
      return false unless @workout.user_id == @user.id
      return false unless @start_index && @end_index
      return false unless @start_index >= 0 && @end_index > @start_index
      return false unless @end_index < points.length
      return true if route?

      selected = points[@start_index..@end_index]
      selected.length >= 2 && selected.map(&:segment_index).uniq.one?
    end

    def derived_attributes(points)
      selected = points[@start_index..@end_index]
      coordinates = selected.map(&:coordinate)
      elevations = selected.map(&:elevation)
      distance = selected.last.distance - selected.first.distance
      ascent, descent = Allure::Gpx::Elevation.ascent_and_descent(
        elevations,
        threshold: Allure::Gpx::Elevation.threshold_for(@workout.elevation_filter)
      )
      factory = RGeo::Geographic.spherical_factory(srid: 4326)

      {
        geom: factory.line_string(coordinates.map { |longitude, latitude| factory.point(longitude, latitude) }),
        start_point: factory.point(*coordinates.first),
        end_point: factory.point(*coordinates.last),
        bounds: bounds_for(coordinates),
        distance: distance,
        ascent: ascent,
        descent: descent,
        min_elevation: Allure::Gpx::Elevation.minimum(elevations),
        max_elevation: Allure::Gpx::Elevation.maximum(elevations),
        elevation_profile: Allure::Segments::ElevationProfile.dump(selected),
        # A workout already on the terrain profile hands its figures over.
        elevation_source: @workout.elevation_source == "dem" ? "dem" : "device",
        elevation_status: @workout.elevation_source == "dem" ? "ready" : nil,
        average_grade: Allure::Segments::Grade.from_elevations(elevations, distance:),
        signature: Allure::Geometry::ShapeSignature.compute(coordinates)
      }
    end

    def bounds_for(coordinates)
      latitudes = coordinates.map(&:last)
      longitudes = coordinates.map(&:first)
      [ latitudes.min, longitudes.min, latitudes.max, longitudes.max ]
    end

    def resolve_tolerance(value)
      return default_tolerance if value == INHERIT_TOLERANCE || value.nil? || value == ""

      integer_or_value(value)
    end

    def default_tolerance
      @kind == "route" ? ROUTE_MATCH_TOLERANCE_METERS : DEFAULT_MATCH_TOLERANCE_METERS
    end

    def integer_or_nil(value)
      value.is_a?(String) ? Integer(value, 10) : Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def integer_or_value(value)
      value.is_a?(String) ? Integer(value, 10) : Integer(value)
    rescue ArgumentError, TypeError
      value
    end
  end
end
