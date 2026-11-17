# frozen_string_literal: true

module Allure
  module Gpx
    # One immutable `<trkpt>`, or its FIT/TCX equivalent. Coordinates follow
    # the repository-wide `[longitude, latitude]` convention only at
    # geometry/GeoJSON boundaries; this value object keeps them as separate
    # named attributes instead.
    #
    # `latitude` and `longitude` are both nil for a point of a positionless
    # recording (an indoor FIT/TCX activity, docs/dev/NO-GPS.md): the point still
    # carries its time and sensor readings, so no timed record is ever
    # discarded for lacking a fix. A point is either fully positioned or fully
    # unpositioned; parsers never build a mixed point.
    #
    # `distance` is the device's own cumulative distance in metres (the FIT
    # `record.distance` field, a TCX trackpoint `DistanceMeters`), nil when the
    # file recorded none. It is the distance source of a positionless
    # recording and never replaces the geodesic measurement of a positioned
    # one.
    #
    # `speed` is the device's own speed reading in metres per second (FIT
    # `enhanced_speed`/`speed`, usually Doppler-derived), never a value the
    # analyzer computes. On a positioned recording it only arbitrates
    # anomalies (docs/dev/WORKOUT.md); on a positionless one it supplies the
    # movement the track cannot measure.
    #
    # `temperature` is the device's own air-temperature reading in °C (FIT
    # `record.temperature`, Garmin GPX `atemp`), nil when the file recorded
    # none (docs/dev/WEATHER.md).
    Point = Data.define(:time, :latitude, :longitude, :elevation, :heart_rate, :cadence, :power, :speed, :distance,
                        :temperature) do
      def initialize(time:, latitude: nil, longitude: nil, elevation: nil, heart_rate: nil, cadence: nil, power: nil,
                     speed: nil, distance: nil, temperature: nil)
        super
      end

      def positioned? = !latitude.nil? && !longitude.nil?
      def elevation? = !elevation.nil?
    end
    # A temperature reading outside this range is a sensor fault, never the air.
    Point::TEMPERATURE_RANGE = (-60..70)
  end
end
