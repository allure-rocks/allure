# frozen_string_literal: true

module Allure
  module Toponyms
    # Great-circle distance in metres between two WGS84 positions, shared by
    # the reverse client, the enricher and the endpoint adjudication.
    module Distance
      RADIUS_METRES = 6_371_000.0

      module_function

      def metres(left_latitude, left_longitude, right_latitude, right_longitude)
        left_latitude_radians = left_latitude * Math::PI / 180.0
        right_latitude_radians = right_latitude * Math::PI / 180.0
        latitude_delta = (right_latitude - left_latitude) * Math::PI / 180.0
        longitude_delta = (right_longitude - left_longitude) * Math::PI / 180.0
        sine_latitude = Math.sin(latitude_delta / 2.0)
        sine_longitude = Math.sin(longitude_delta / 2.0)
        value = (sine_latitude**2) +
          (Math.cos(left_latitude_radians) * Math.cos(right_latitude_radians) * (sine_longitude**2))
        RADIUS_METRES * 2.0 * Math.atan2(Math.sqrt(value), Math.sqrt([ 1.0 - value, 0.0 ].max))
      end
    end
  end
end
