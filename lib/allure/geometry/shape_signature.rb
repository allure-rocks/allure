# frozen_string_literal: true

module Allure
  module Geometry
    module ShapeSignature
      DIMENSIONS = 64
      SAMPLE_COUNT = DIMENSIONS + 2
      PRECISION = 6

      module_function

      def compute(coordinates)
        samples = Allure::Geometry::Resampler.resample(coordinates, count: SAMPLE_COUNT)
        projected = project(samples)

        projected.each_cons(3).map do |previous, current, following|
          incoming_x = current[0] - previous[0]
          incoming_y = current[1] - previous[1]
          outgoing_x = following[0] - current[0]
          outgoing_y = following[1] - current[1]
          next 0.0 if (incoming_x.zero? && incoming_y.zero?) || (outgoing_x.zero? && outgoing_y.zero?)

          angle = Math.atan2(
            (incoming_x * outgoing_y) - (incoming_y * outgoing_x),
            (incoming_x * outgoing_x) + (incoming_y * outgoing_y)
          )
          angle = Math::PI if angle == -Math::PI
          normalized = angle / Math::PI
          normalized.round(PRECISION)
        end.tap(&:freeze)
      end

      def project(points)
        mean_latitude = points.sum(&:last) / points.length
        reference_longitude = points.first.first
        longitude_scale = Math.cos(Allure::Gpx::Geo.to_radians(mean_latitude))
        unwrapped_longitudes = unwrap_longitudes(points)

        points.zip(unwrapped_longitudes).map do |(longitude, latitude), unwrapped_longitude|
          [
            Allure::Gpx::Geo.to_radians(unwrapped_longitude - reference_longitude) * longitude_scale,
            Allure::Gpx::Geo.to_radians(latitude - mean_latitude)
          ]
        end
      end

      def unwrap_longitudes(points)
        points.drop(1).each_with_object([ points.first.first ]) do |point, result|
          result << result.last + Allure::Gpx::Geo.normalize_longitude_delta(point.first - points[result.length - 1].first)
        end
      end
    end
  end
end
