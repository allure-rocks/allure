# frozen_string_literal: true

module Allure
  module Weather
    # Wind vector arithmetic. Directions are meteorological: the bearing the
    # wind blows *from*, clockwise from north. `u` points east and `v` north,
    # both the direction the air moves *to*.
    module Wind
      RADIANS = Math::PI / 180.0

      module_function

      def components(speed, from_degrees)
        radians = from_degrees.to_f * RADIANS
        [ -speed.to_f * Math.sin(radians), -speed.to_f * Math.cos(radians) ]
      end

      def direction(u, v)
        return nil if u.abs < 1e-9 && v.abs < 1e-9

        ((Math.atan2(-u, -v) / RADIANS) + 360.0) % 360.0
      end

      # The signed angle from the travel bearing to the wind's origin, in
      # (-180, 180]: 0 is a wind straight from ahead.
      def relative_angle(from_degrees, bearing)
        angle = (from_degrees.to_f - bearing.to_f) % 360.0
        angle > 180.0 ? angle - 360.0 : angle
      end

      # The wind component against the direction of travel: positive is a
      # headwind, negative a tailwind.
      def headwind(speed, from_degrees, bearing)
        speed.to_f * Math.cos(relative_angle(from_degrees, bearing) * RADIANS)
      end

      def sector(from_degrees, bearing)
        angle = relative_angle(from_degrees, bearing).abs
        if angle <= 45.0 then :head
        elsif angle >= 135.0 then :tail
        else :cross
        end
      end

      # A speed-weighted circular mean of origins, nil when calm.
      def mean_direction(pairs)
        u = 0.0
        v = 0.0
        pairs.each do |speed, degrees|
          next if speed.nil? || degrees.nil?

          du, dv = components(speed, degrees)
          u += du
          v += dv
        end
        direction(u, v)
      end

      # Initial great-circle bearing from one position to another, degrees.
      def bearing(latitude1, longitude1, latitude2, longitude2)
        phi1 = latitude1 * RADIANS
        phi2 = latitude2 * RADIANS
        delta = (longitude2 - longitude1) * RADIANS
        y = Math.sin(delta) * Math.cos(phi2)
        x = Math.cos(phi1) * Math.sin(phi2) - Math.sin(phi1) * Math.cos(phi2) * Math.cos(delta)
        ((Math.atan2(y, x) / RADIANS) + 360.0) % 360.0
      end
    end
  end
end
