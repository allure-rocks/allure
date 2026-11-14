# frozen_string_literal: true

module Allure
  module Geometry
    # The symmetric discrete Hausdorff distance between two polylines, in
    # meters. Unlike the direction-coupled Fréchet distance, the geometries are
    # compared as point sets: two recordings of the same circuit started at
    # different points measure near zero. Each sampled point is measured against
    # the other polyline's segments, so a coarse sample never inflates the
    # result at a corner. Used to recognise an already detected loop
    # (PLAN_SEGMENTS.md §7.3).
    module Hausdorff
      DEFAULT_SAMPLES = 64

      module_function

      def symmetric_distance(first, second, samples: DEFAULT_SAMPLES)
        [
          directed(resample(first, samples), second),
          directed(resample(second, samples), first)
        ].max
      end

      # Max over `points` of the shortest distance to `polyline`, measured
      # against its segments rather than only its vertices.
      def directed(points, polyline)
        frame = local_frame(polyline)
        points.map { |point| distance_to_polyline(point, frame) }.max || 0.0
      end

      def resample(coordinates, samples)
        Allure::Geometry::Resampler.resample(coordinates, count: samples)
      end

      # An equirectangular frame anchored on the reference polyline, mirroring
      # `Allure::Geometry::Projection`, with longitudes unwrapped so the
      # antimeridian never produces a spurious jump.
      def local_frame(polyline)
        reference_longitude = polyline.first.first
        mean_latitude = polyline.sum { |coordinate| coordinate.last } / polyline.length
        longitude_scale = Math.cos(Allure::Gpx::Geo.to_radians(mean_latitude))
        unwrapped = Allure::Geometry::Projection.unwrap_longitudes(polyline)

        {
          reference_longitude:,
          mean_latitude:,
          longitude_scale:,
          points: unwrapped.each_with_index.map do |longitude, index|
            local_xy(longitude, polyline[index].last, reference_longitude, mean_latitude, longitude_scale)
          end
        }
      end

      def distance_to_polyline(coordinate, frame)
        target = local_xy(
          frame[:reference_longitude] +
            Allure::Gpx::Geo.normalize_longitude_delta(coordinate.first - frame[:reference_longitude]),
          coordinate.last,
          frame[:reference_longitude],
          frame[:mean_latitude],
          frame[:longitude_scale]
        )

        best = Float::INFINITY
        points = frame[:points]
        index = 0
        while index < points.length - 1
          distance = segment_distance(target, points[index], points[index + 1])
          best = distance if distance < best
          index += 1
        end
        best
      end

      def segment_distance(target, first, second)
        delta_x = second[0] - first[0]
        delta_y = second[1] - first[1]
        length_squared = (delta_x**2) + (delta_y**2)
        return Math.hypot(target[0] - first[0], target[1] - first[1]) if length_squared.zero?

        fraction = (((target[0] - first[0]) * delta_x) + ((target[1] - first[1]) * delta_y)).fdiv(length_squared)
        fraction = fraction.clamp(0.0, 1.0)

        Math.hypot(
          target[0] - (first[0] + (delta_x * fraction)),
          target[1] - (first[1] + (delta_y * fraction))
        )
      end

      def local_xy(longitude, latitude, reference_longitude, mean_latitude, longitude_scale)
        [
          Allure::Gpx::Geo::EARTH_RADIUS_METRES *
            Allure::Gpx::Geo.to_radians(longitude - reference_longitude) * longitude_scale,
          Allure::Gpx::Geo::EARTH_RADIUS_METRES * Allure::Gpx::Geo.to_radians(latitude - mean_latitude)
        ]
      end

      private_class_method :directed, :resample, :local_frame, :distance_to_polyline, :segment_distance, :local_xy
    end
  end
end
