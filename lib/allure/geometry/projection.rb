# frozen_string_literal: true

module Allure
  module Geometry
    module Projection
      Result = Data.define(
        :coordinate,
        :segment_index,
        :fraction,
        :distance_meters,
        :distance_along_meters,
        :time
      ) do
        def initialize(coordinate:, segment_index:, fraction:, distance_meters:, distance_along_meters:, time:)
          super
        end
      end

      EARTH_RADIUS_METRES = Allure::Gpx::Geo::EARTH_RADIUS_METRES

      module_function

      def project(target:, polyline:, times:)
        target = normalize_coordinate(target)
        points = normalize_coordinates(polyline)
        times = Array(times)
        raise ArgumentError, "times must match the polyline" unless times.length == points.length

        projected = local_coordinates(points, target)
        target_xy = projected[:target]
        cumulative_lengths = cumulative_lengths(points)
        best = nil

        points.each_cons(2).with_index do |(first, second), index|
          first_xy = projected[:points][index]
          second_xy = projected[:points][index + 1]
          fraction = projection_fraction(target_xy, first_xy, second_xy)
          coordinate = interpolate(first, second, fraction)
          distance_meters = horizontal_distance(target, coordinate)
          candidate = [ distance_meters, index, fraction, coordinate ]
          best = candidate if best.nil? || distance_meters < best[0]
        end

        distance_meters, segment_index, fraction, coordinate = best
        edge_distance = cumulative_lengths[segment_index + 1] - cumulative_lengths[segment_index]
        time = times[segment_index] + ((times[segment_index + 1] - times[segment_index]) * fraction)

        Result.new(
          coordinate: coordinate,
          segment_index: segment_index,
          fraction: fraction,
          distance_meters: distance_meters,
          distance_along_meters: cumulative_lengths[segment_index] + (edge_distance * fraction),
          time: time
        )
      end

      def normalize_coordinates(coordinates)
        points = Array(coordinates).map { |coordinate| normalize_coordinate(coordinate) }
        raise ArgumentError, "polyline requires at least two coordinates" if points.length < 2

        points
      rescue TypeError, ArgumentError => error
        raise error if error.message.match?(/polyline|coordinate/)

        raise ArgumentError, "invalid coordinates", cause: error
      end

      def normalize_coordinate(coordinate)
        values = Array(coordinate)
        raise ArgumentError, "invalid coordinate" unless values.length == 2

        longitude, latitude = values
        longitude = Float(longitude)
        latitude = Float(latitude)
        unless longitude.finite? && latitude.finite? && longitude.between?(-180, 180) && latitude.between?(-90, 90)
          raise ArgumentError, "invalid coordinate"
        end

        [ longitude, latitude ].freeze
      rescue TypeError, ArgumentError
        raise ArgumentError, "invalid coordinate"
      end

      def local_coordinates(points, target)
        mean_latitude = points.sum(&:last) / points.length
        reference_longitude = points.first.first
        longitude_scale = Math.cos(Allure::Gpx::Geo.to_radians(mean_latitude))
        unwrapped_longitudes = unwrap_longitudes(points)
        target_longitude = reference_longitude +
                           Allure::Gpx::Geo.normalize_longitude_delta(target.first - reference_longitude)

        {
          points: points.zip(unwrapped_longitudes).map do |(longitude, latitude), unwrapped_longitude|
            local_point(unwrapped_longitude, latitude, reference_longitude, mean_latitude, longitude_scale)
          end,
          target: local_point(target_longitude, target.last, reference_longitude, mean_latitude, longitude_scale)
        }
      end

      def unwrap_longitudes(points)
        points.drop(1).each_with_object([ points.first.first ]) do |point, result|
          result << result.last + Allure::Gpx::Geo.normalize_longitude_delta(point.first - points[result.length - 1].first)
        end
      end

      def local_point(longitude, latitude, reference_longitude, mean_latitude, longitude_scale)
        [
          EARTH_RADIUS_METRES * Allure::Gpx::Geo.to_radians(longitude - reference_longitude) * longitude_scale,
          EARTH_RADIUS_METRES * Allure::Gpx::Geo.to_radians(latitude - mean_latitude)
        ]
      end

      def projection_fraction(target, first, second)
        delta_x = second[0] - first[0]
        delta_y = second[1] - first[1]
        length_squared = (delta_x**2) + (delta_y**2)
        return 0.0 if length_squared.zero?

        (((target[0] - first[0]) * delta_x) + ((target[1] - first[1]) * delta_y))
          .fdiv(length_squared)
          .clamp(0.0, 1.0)
      end

      def cumulative_lengths(points)
        [ 0.0 ].tap do |lengths|
          points.each_cons(2) do |first, second|
            lengths << lengths.last + horizontal_distance(first, second)
          end
        end
      end

      def horizontal_distance(first, second)
        Allure::Gpx::Geo.horizontal_distance(first[1], first[0], second[1], second[0])
      end

      def interpolate(first, second, fraction)
        longitude_delta = Allure::Gpx::Geo.normalize_longitude_delta(second.first - first.first)
        longitude = first.first + (longitude_delta * fraction)
        longitude -= 360.0 while longitude > 180.0
        longitude += 360.0 while longitude < -180.0

        [ longitude, first.last + ((second.last - first.last) * fraction) ].freeze
      end
    end
  end
end
