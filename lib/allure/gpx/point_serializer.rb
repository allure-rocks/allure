# frozen_string_literal: true

module Allure
  module Gpx
    # Writes the compact per-point JSON contract documented in
    # PLAN_M1.md section 5.4. This is the only place that shape is produced;
    # chart extraction (Slice 5) must read these same key constants.
    module PointSerializer
      KEY_TIME = "t"
      KEY_DISTANCE = "d"
      KEY_LATITUDE = "lat"
      KEY_LONGITUDE = "lon"
      KEY_ELEVATION = "ele"
      KEY_SPEED = "v"
      KEY_HEART_RATE = "hr"
      KEY_CADENCE = "cad"
      KEY_POWER = "pw"
      KEY_TEMPERATURE = "temp"

      module_function

      def serialize(
        time_offset_seconds:,
        cumulative_distance_metres:,
        latitude: nil,
        longitude: nil,
        elevation: nil,
        speed_metres_per_second: nil,
        heart_rate: nil,
        cadence: nil,
        power: nil,
        temperature: nil
      )
        hash = {
          KEY_TIME => time_offset_seconds,
          KEY_DISTANCE => cumulative_distance_metres.round(1)
        }
        # A point of a positionless recording carries no coordinates at all:
        # the keys are absent, never null, so every coordinate consumer fails
        # loudly instead of reading a meaningless 0° position
        # (PLAN_NO_GPS.md).
        if !latitude.nil? && !longitude.nil?
          hash[KEY_LATITUDE] = latitude
          hash[KEY_LONGITUDE] = longitude
        end
        hash[KEY_ELEVATION] = elevation.round(1) unless elevation.nil?
        hash[KEY_SPEED] = speed_metres_per_second.round(2) unless speed_metres_per_second.nil?
        hash[KEY_HEART_RATE] = heart_rate unless heart_rate.nil?
        hash[KEY_CADENCE] = cadence unless cadence.nil?
        hash[KEY_POWER] = power unless power.nil?
        hash[KEY_TEMPERATURE] = temperature.round unless temperature.nil?
        hash
      end
    end
  end
end
