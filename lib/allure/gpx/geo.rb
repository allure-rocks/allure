# frozen_string_literal: true

module Allure
  module Gpx
    # Pure horizontal/3D distance calculation between two coordinates.
    # See PLAN_M1.md section 8.1 for the locked algorithm.
    module Geo
      EARTH_RADIUS_METRES = 6_378_137.0
      SHORT_DELTA_THRESHOLD_DEGREES = 0.2

      module_function

      # Distance in metres between two Points. Uses 3D distance when both
      # points carry an elevation, otherwise falls back to 2D. Elevation
      # `0.0` is a valid, present value and participates in 3D distance.
      def distance(point_a, point_b)
        horizontal = horizontal_distance(point_a.latitude, point_a.longitude, point_b.latitude, point_b.longitude)
        return horizontal unless point_a.elevation? && point_b.elevation?

        elevation_delta = point_b.elevation - point_a.elevation
        Math.sqrt((horizontal**2) + (elevation_delta**2))
      end

      def horizontal_distance(latitude_a, longitude_a, latitude_b, longitude_b)
        delta_latitude = latitude_b - latitude_a
        delta_longitude = normalize_longitude_delta(longitude_b - longitude_a)

        if delta_latitude.abs <= SHORT_DELTA_THRESHOLD_DEGREES && delta_longitude.abs <= SHORT_DELTA_THRESHOLD_DEGREES
          equirectangular_distance(latitude_a, delta_latitude, delta_longitude)
        else
          haversine_distance(latitude_a, longitude_a, latitude_b, longitude_b)
        end
      end

      # Shortest signed delta between two longitudes, normalized to
      # `[-180, 180]`, so a crossing of the antimeridian never produces a
      # spurious near-360-degree jump.
      def normalize_longitude_delta(delta)
        normalized = delta % 360.0
        normalized -= 360.0 if normalized > 180.0
        normalized
      end

      def equirectangular_distance(latitude_a, delta_latitude, delta_longitude)
        x = to_radians(delta_longitude) * Math.cos(to_radians(latitude_a))
        y = to_radians(delta_latitude)
        Math.sqrt((x**2) + (y**2)) * EARTH_RADIUS_METRES
      end

      def haversine_distance(latitude_a, longitude_a, latitude_b, longitude_b)
        delta_latitude = to_radians(latitude_b - latitude_a)
        delta_longitude = to_radians(normalize_longitude_delta(longitude_b - longitude_a))

        a = (Math.sin(delta_latitude / 2)**2) +
            (Math.cos(to_radians(latitude_a)) * Math.cos(to_radians(latitude_b)) * (Math.sin(delta_longitude / 2)**2))
        c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        EARTH_RADIUS_METRES * c
      end

      def to_radians(degrees) = degrees * Math::PI / 180.0
    end
  end
end
