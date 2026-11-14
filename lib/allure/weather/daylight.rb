# frozen_string_literal: true

module Allure
  module Weather
    # Whether the sun was above the horizon at one instant and position
    # (PLAN_WEATHER.md §3). The provider is asked nothing extra: its ten
    # hourly variables fill one billed call, and an eleventh would double it.
    #
    # The solar elevation follows the standard low-precision ephemeris (mean
    # anomaly, ecliptic longitude, declination, hour angle), accurate to about
    # a minute at mid-latitudes — far finer than a 0.1° cell (~11 km) and the
    # provider's own hourly step. `-0.833°` is the usual sunrise and sunset
    # altitude once refraction and the solar radius are accounted for.
    module Daylight
      HORIZON_DEGREES = -0.833
      J2000 = 2_451_545.0
      RADIANS = Math::PI / 180.0
      SECONDS_PER_DAY = 86_400.0
      OBLIQUITY = 23.439 - 0.00000036
      # 2000-01-01 12:00 UTC, the J2000.0 epoch, as a Unix timestamp.
      J2000_EPOCH = 946_728_000

      module_function

      # `time` is any object answering `to_f` (seconds since the Unix epoch);
      # `latitude` and `longitude` are degrees, [−90, 90] and [−180, 180].
      def day?(time:, latitude:, longitude:)
        elevation(time:, latitude:, longitude:) > HORIZON_DEGREES
      end

      # The sun's apparent altitude in degrees, negative below the horizon.
      def elevation(time:, latitude:, longitude:)
        days = days_since_j2000(time)
        declination = declination(days)
        right_ascension = right_ascension(days)
        hour_angle = hour_angle(days, right_ascension, longitude)

        sin_latitude = Math.sin(latitude * RADIANS)
        cos_latitude = Math.cos(latitude * RADIANS)
        sin_declination = Math.sin(declination * RADIANS)
        cos_declination = Math.cos(declination * RADIANS)
        height = sin_latitude * sin_declination +
          cos_latitude * cos_declination * Math.cos(hour_angle * RADIANS)
        Math.asin(height.clamp(-1.0, 1.0)) / RADIANS
      end

      def days_since_j2000(time)
        (time.to_f - J2000_EPOCH) / SECONDS_PER_DAY
      end

      # Mean anomaly of the sun, degrees.
      def mean_anomaly(days)
        (357.529 + 0.98560028 * days) % 360.0
      end

      # Ecliptic longitude of the sun, degrees.
      def ecliptic_longitude(days)
        anomaly = mean_anomaly(days) * RADIANS
        (280.459 + 0.98564736 * days + 1.915 * Math.sin(anomaly) + 0.020 * Math.sin(2 * anomaly)) % 360.0
      end

      # Declination of the sun, degrees.
      def declination(days)
        longitude = ecliptic_longitude(days) * RADIANS
        Math.asin(Math.sin(OBLIQUITY * RADIANS) * Math.sin(longitude)) / RADIANS
      end

      # Right ascension of the sun, degrees.
      def right_ascension(days)
        longitude = ecliptic_longitude(days) * RADIANS
        (Math.atan2(Math.cos(OBLIQUITY * RADIANS) * Math.sin(longitude), Math.cos(longitude)) / RADIANS) % 360.0
      end

      # The sun's hour angle at a longitude, degrees. The Earth's rotation is
      # a constant plus a sidereal day per solar day; no leap-second bookkeeping
      # is needed at this precision.
      def hour_angle(days, right_ascension, longitude)
        (18.697374558 + 24.06570982441908 * days) * 15.0 + longitude - right_ascension
      end
    end
  end
end
