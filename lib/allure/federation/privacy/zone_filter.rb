# frozen_string_literal: true

module Allure
  module Federation
    module Privacy
      class ZoneFilter
        EARTH_RADIUS_METRES = Allure::Gpx::Geo::EARTH_RADIUS_METRES
        ANGLE_EPSILON = 1e-10

        class InvalidInput < ArgumentError; end
        class FilteringError < StandardError; end

        # `preserve_start` / `preserve_finish` exempt the corresponding
        # publication endpoint from zone filtering: the source points stay
        # visible from the endpoint up to the route's first exit from every
        # zone (start) or from its last entry to the end (finish). Interior
        # points remain filtered, and a segment that never leaves a zone is
        # filtered whole rather than exposing its interior.
        def initialize(segments:, zones:, preserve_start: false, preserve_finish: false)
          @segments = segments
          @zones = zones
          @preserve_start = preserve_start == true
          @preserve_finish = preserve_finish == true
        end

        def call
          source_segments = normalize_segments(@segments)
          zones = normalize_zones(@zones)
          last_segment_index = source_segments.length - 1
          filtered_segments = source_segments.each_with_index.flat_map do |segment, index|
            first_segment = index.zero?
            last_segment = index == last_segment_index
            filter_segment(
              segment,
              zones,
              preserve_start: @preserve_start && first_segment,
              preserve_finish: @preserve_finish && last_segment
            )
          end
          visible_points_count = filtered_segments.sum(&:length)
          interior_points_removed = interior_points_removed?(source_segments, filtered_segments)

          FilteredTrack.new(
            segments: filtered_segments,
            visible_points_count:,
            points_removed: visible_points_count < source_segments.sum(&:length),
            interior_points_removed:,
            bounds: bounds_for(filtered_segments),
            usable: filtered_segments.any? { |segment| segment.length >= 2 }
          )
        rescue InvalidInput, FilteringError
          raise
        rescue StandardError => error
          raise FilteringError, "privacy filtering failed", cause: error
        end

        def covered?(coordinate)
          point = normalize_coordinate(coordinate)
          point_hidden?(point, normalize_zones(@zones))
        rescue InvalidInput, FilteringError
          raise
        rescue StandardError => error
          raise FilteringError, "privacy-zone coverage check failed", cause: error
        end

        private

        def normalize_segments(segments)
          unless segments.is_a?(Array) && segments.any?
            raise InvalidInput, "at least one route segment is required"
          end

          segments.map do |segment|
            unless segment.is_a?(Array) && segment.length >= 2
              raise InvalidInput, "route segments require at least two points"
            end

            segment.map { |point| normalize_coordinate(point) }
          end
        end

        def normalize_zones(zones)
          unless zones.is_a?(Array)
            raise InvalidInput, "privacy zones must be an array"
          end

          zones.map do |zone|
            center, radius = if zone.is_a?(Zone)
              [ zone.center, zone.radius_meters ]
            elsif zone.is_a?(Hash)
              [ zone[:center] || zone["center"], zone[:radius_meters] || zone["radius_meters"] ]
            else
              raise InvalidInput, "invalid privacy zone"
            end

            [ normalize_coordinate(center), normalize_radius(radius) ]
          end
        end

        def normalize_coordinate(coordinate)
          unless coordinate.is_a?(Array) && coordinate.length == 2 && coordinate.all? { |value| value.is_a?(Numeric) }
            raise InvalidInput, "coordinates must be numeric [longitude, latitude] pairs"
          end

          longitude, latitude = coordinate.map(&:to_f)
          unless longitude.finite? && latitude.finite? && longitude.between?(-180, 180) && latitude.between?(-90, 90)
            raise InvalidInput, "invalid route coordinate"
          end

          [ longitude, latitude ]
        end

        def normalize_radius(radius)
          value = radius.to_f if radius.is_a?(Numeric)
          unless value&.finite? && value == value.round && value.between?(1, 10_000)
            raise InvalidInput, "privacy-zone radius must be an integer between 1 and 10000 metres"
          end

          value.to_i
        end

        def filter_segment(points, zones, preserve_start:, preserve_finish:)
          preserved = preserved_flags(points, zones, preserve_start:, preserve_finish:)
          runs = []
          current_run = []
          previous_point = nil
          previous_visible = false
          previous_preserved = false

          points.each_with_index do |point, index|
            exempt = preserved[index]
            hidden = !exempt && point_hidden?(point, zones)
            if hidden
              append_run(runs, current_run)
              current_run = []
            elsif previous_visible && !(previous_preserved && exempt) && edge_blocked?(previous_point, point, zones)
              append_run(runs, current_run)
              current_run = [ point ]
            else
              current_run << point
            end

            previous_point = point
            previous_visible = !hidden
            previous_preserved = exempt
          end
          append_run(runs, current_run)

          runs
        end

        # A preserved endpoint keeps its source points until the first point
        # outside every zone (start) or from the last point outside every zone
        # (finish). A segment with no zone-free point keeps no exemption at all:
        # preserving the endpoint there would expose the zone interior the
        # filter exists to remove, so the route fails closed instead.
        def preserved_flags(points, zones, preserve_start:, preserve_finish:)
          return Array.new(points.length, false) unless preserve_start || preserve_finish

          first_visible = points.index { |point| !point_hidden?(point, zones) }
          return Array.new(points.length, false) if first_visible.nil?

          last_visible = points.rindex { |point| !point_hidden?(point, zones) }
          flags = Array.new(points.length, false)
          (0..first_visible).each { |index| flags[index] = true } if preserve_start
          (last_visible..(points.length - 1)).each { |index| flags[index] = true } if preserve_finish
          flags
        end

        def append_run(runs, run)
          runs << run if run.length >= 2
        end

        def interior_points_removed?(source_segments, filtered_segments)
          source_points = source_segments.flatten(1)
          interior_points = source_points[1, source_points.length - 2] || []
          visible_counts = filtered_segments.flatten(1).tally

          interior_points.any? do |point|
            if visible_counts[point].to_i.positive?
              visible_counts[point] -= 1
              false
            else
              true
            end
          end
        end

        def point_hidden?(point, zones)
          zones.any? do |center, radius|
            horizontal_distance(point, center) <= radius
          end
        end

        def edge_blocked?(start_point, end_point, zones)
          zones.any? do |center, radius|
            geodesic_segment_distance(center, start_point, end_point) <= radius
          end
        end

        def horizontal_distance(first, second)
          Allure::Gpx::Geo.horizontal_distance(first[1], first[0], second[1], second[0])
        end

        # Finds the closest point on the minor great-circle arc. Endpoint
        # checks are retained for degenerate or antipodal pairs.
        def geodesic_segment_distance(center, start_point, end_point)
          start_vector = vector(start_point)
          end_vector = vector(end_point)
          center_vector = vector(center)
          normal = cross(start_vector, end_vector)
          normal_length = norm(normal)
          endpoint_distance = [ horizontal_distance(center, start_point), horizontal_distance(center, end_point) ].min
          return endpoint_distance if normal_length <= ANGLE_EPSILON

          projected = subtract(center_vector, scale(normal, dot(center_vector, normal) / (normal_length**2)))
          projected_length = norm(projected)
          return endpoint_distance if projected_length <= ANGLE_EPSILON

          candidates = [ scale(projected, 1.0 / projected_length), scale(projected, -1.0 / projected_length) ]
          arc_distance = candidates.filter_map do |candidate|
            next unless on_minor_arc?(start_vector, end_vector, candidate)

            angular_distance(center_vector, candidate) * EARTH_RADIUS_METRES
          end.min

          [ endpoint_distance, arc_distance || Float::INFINITY ].min
        end

        def vector(coordinate)
          latitude = Allure::Gpx::Geo.to_radians(coordinate[1])
          longitude = Allure::Gpx::Geo.to_radians(coordinate[0])
          cosine = Math.cos(latitude)
          [ cosine * Math.cos(longitude), cosine * Math.sin(longitude), Math.sin(latitude) ]
        end

        def cross(first, second)
          [
            (first[1] * second[2]) - (first[2] * second[1]),
            (first[2] * second[0]) - (first[0] * second[2]),
            (first[0] * second[1]) - (first[1] * second[0])
          ]
        end

        def dot(first, second) = first.zip(second).sum { |left, right| left * right }
        def norm(vector) = Math.sqrt(dot(vector, vector))
        def scale(vector, factor) = vector.map { |value| value * factor }
        def subtract(first, second) = first.zip(second).map { |left, right| left - right }

        def angular_distance(first, second)
          Math.acos(dot(first, second).clamp(-1.0, 1.0))
        end

        def on_minor_arc?(start_vector, end_vector, candidate)
          segment_angle = angular_distance(start_vector, end_vector)
          candidate_angle = angular_distance(start_vector, candidate) + angular_distance(candidate, end_vector)
          candidate_angle <= segment_angle + ANGLE_EPSILON
        end

        def bounds_for(segments)
          points = segments.flatten(1)
          return if points.empty?

          longitudes = points.map(&:first)
          latitudes = points.map(&:last)
          [ latitudes.min, longitudes.min, latitudes.max, longitudes.max ]
        end
      end
    end
  end
end
