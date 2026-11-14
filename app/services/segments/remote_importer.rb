# frozen_string_literal: true

module Segments
  # Turns a received course into a private, owner-only local segment,
  # re-deriving the geometry, distance, and signature from the verified remote
  # track. Remote course metrics are display-only; the copy never matches
  # against the remote row (PLAN_SEGMENTS_FEDERATION.md §12.4).
  class RemoteImporter
    class ImportError < StandardError; end

    Result = Data.define(:segment, :warnings)

    def initialize(user:, remote_segment:)
      @user = user
      @remote_segment = remote_segment
      @warnings = []
    end

    def call!
      coordinates = validated_coordinates!
      segment = @user.segments.create_or_find_by!(remote_segment: @remote_segment) do |record|
        record.assign_attributes(attributes_for(coordinates))
      end
      Result.new(segment:, warnings: @warnings)
    rescue ActiveRecord::RecordInvalid => error
      raise ImportError,
            I18n.t("segments.remote_copy.errors.invalid", message: error.record.errors.full_messages.to_sentence)
    end

    private

    def validated_coordinates!
      raise ImportError, I18n.t("segments.remote_copy.errors.unavailable") unless @remote_segment.active?
      raise ImportError, I18n.t("segments.remote_copy.errors.purged") if @remote_segment.location_data_purged?
      unless @remote_segment.attachments.cached.exists?(kind: "gpx")
        raise ImportError, I18n.t("segments.remote_copy.errors.pending_media")
      end

      coordinates = extract_coordinates
      raise ImportError, I18n.t("segments.remote_copy.errors.no_track") unless coordinates

      coordinates
    end

    # The remote course is exactly one LineString. A multi-feature track is not
    # representable as one local geography and is rejected rather than
    # flattened.
    def extract_coordinates
      track = @remote_segment.representation["track"]
      return unless track.is_a?(Hash) && track["type"] == "FeatureCollection"

      features = track["features"]
      return unless features.is_a?(Array) && features.length == 1

      geometry = features.first["geometry"]
      return unless geometry.is_a?(Hash) && geometry["type"] == "LineString"

      points = geometry["coordinates"]
      return unless points.is_a?(Array) && points.length >= 2

      result = points.map { |point| [ Float(point[0]), Float(point[1]) ] }
      return unless result.all? { |longitude, latitude| valid_coordinate?(longitude, latitude) }

      result
    rescue ArgumentError, TypeError, NoMethodError
      nil
    end

    def valid_coordinate?(longitude, latitude)
      longitude.finite? && latitude.finite? &&
        longitude.between?(-180, 180) && latitude.between?(-90, 90)
    end

    def attributes_for(coordinates)
      factory = RGeo::Geographic.spherical_factory(srid: 4326)
      distance = geodesic_distance(coordinates)
      ascent = display_metric("ascent")
      descent = display_metric("descent")
      representation = @remote_segment.representation

      {
        name: (representation["name"].presence || @remote_segment.name).first(120),
        description: representation["description"],
        kind: "segment",
        sport: resolved_sport,
        visibility: "private",
        active: true,
        match_tolerance_meters: match_tolerance(representation),
        matcher_version: Allure::Segments::Matcher::VERSION,
        source_workout: nil,
        source_start_index: nil,
        source_end_index: nil,
        geom: factory.line_string(coordinates.map { |longitude, latitude| factory.point(longitude, latitude) }),
        start_point: factory.point(*coordinates.first),
        end_point: factory.point(*coordinates.last),
        bounds: bounds_for(coordinates),
        distance:,
        ascent:,
        descent:,
        average_grade: average_grade(representation, ascent, descent, distance),
        min_elevation: nil,
        max_elevation: nil,
        signature: Allure::Geometry::ShapeSignature.compute(coordinates)
      }
    end

    def bounds_for(coordinates)
      latitudes = coordinates.map(&:last)
      longitudes = coordinates.map(&:first)
      [ latitudes.min, longitudes.min, latitudes.max, longitudes.max ]
    end

    def geodesic_distance(coordinates)
      coordinates.each_cons(2).sum do |(longitude_a, latitude_a), (longitude_b, latitude_b)|
        Allure::Gpx::Geo.horizontal_distance(latitude_a, longitude_a, latitude_b, longitude_b)
      end
    end

    def display_metric(key)
      value = @remote_segment.representation[key]
      return unless value.is_a?(Numeric) && value.to_f.finite? && value.to_f >= 0

      value.to_f
    end

    def average_grade(representation, ascent, descent, distance)
      grade = representation["average_grade"]
      return grade.to_f if grade.is_a?(Numeric) && grade.to_f.finite?

      Allure::Segments::Grade.from_totals(ascent:, descent:, distance:)
    end

    def match_tolerance(representation)
      value = representation["match_tolerance"]
      return value.to_i if value.is_a?(Numeric) && value.to_i.between?(5, 100)

      Segments::Creator::DEFAULT_MATCH_TOLERANCE_METERS
    end

    # A resolvable slug becomes the copy's sport; an absent slug is an
    # all-sports course, and an unknown slug imports as all-sports with a
    # warning rather than blocking a useful copy.
    def resolved_sport
      slug = @remote_segment.representation["sport_slug"]
      return nil if slug.blank?

      sport = Sport.find_by(slug:)
      @warnings << I18n.t("segments.remote_copy.warnings.unknown_sport", slug:) unless sport
      sport
    end
  end
end
