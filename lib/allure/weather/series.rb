# frozen_string_literal: true

module Allure
  module Weather
    # The weather the athlete met, one row per sample of the plan
    # (docs/dev/WEATHER.md): the values of the cell they were in, interpolated
    # between the provider's two bounding hours. Wind speed is interpolated
    # linearly and its direction through the u/v components, never by
    # averaging angles; precipitation is the provider's sum over the hour that
    # contains the instant; the weather code is the nearest hour's.
    #
    # Stored values stay SI: °C, %, mm, hPa, m/s, degrees the wind blows from.
    class Series
      ROW_KEYS = {
        time: "t", temperature: "temp", apparent_temperature: "feels", humidity: "rh",
        precipitation: "precip", weather_code: "code", cloud_cover: "cloud", pressure: "pres",
        wind_speed: "wind", wind_direction: "dir", wind_gusts: "gust", day: "day"
      }.freeze

      Row = Data.define(*ROW_KEYS.keys) do
        # Every member is optional: a hand-built row (a spec, a summary read)
        # names only what it has.
        def initialize(**attributes)
          super(**{ day: nil }.merge(attributes))
        end

        def self.from_h(hash)
          new(**ROW_KEYS.to_h { |attribute, key| [ attribute, hash[key] ] })
        end

        def to_h = ROW_KEYS.to_h { |attribute, key| [ key, public_send(attribute) ] }

        def usable? = !temperature.nil? && !wind_speed.nil? && !wind_direction.nil?
      end

      LINEAR = {
        temperature: "temperature_2m", apparent_temperature: "apparent_temperature",
        humidity: "relative_humidity_2m", cloud_cover: "cloud_cover", pressure: "surface_pressure",
        wind_speed: "wind_speed_10m", wind_gusts: "wind_gusts_10m"
      }.freeze
      PRECISION = {
        temperature: 1, apparent_temperature: 1, humidity: 0, cloud_cover: 0, pressure: 1,
        wind_speed: 1, wind_gusts: 1, precipitation: 1, wind_direction: 0
      }.freeze

      # `responses` is aligned with the plan's cells (`OpenMeteo#hourly`);
      # `samples` carry `time` (Unix seconds) and `cell`. `cells` are those
      # same locations, read for the day/night flag alone — the provider is
      # asked nothing extra for it.
      def self.call(responses:, samples:, cells: []) = new(responses:, samples:, cells:).call

      def initialize(responses:, samples:, cells: [])
        @responses = responses
        @samples = samples
        @cells = Array(cells)
      end

      def call
        @samples.map { |sample| row_for(sample) }
      end

      def self.complete?(rows) = rows.any? && rows.all?(&:usable?)

      private

      def row_for(sample)
        response = @responses[sample.cell] || {}
        times = Array(response["time"])
        time = sample.time
        index = times.rindex { |hour| hour <= time }
        return empty_row(time) if index.nil?

        following = [ index + 1, times.length - 1 ].min
        span = times[following] - times[index]
        fraction = span.positive? ? (time - times[index]).to_f / span : 0.0

        values = LINEAR.to_h do |attribute, variable|
          [ attribute, rounded(attribute, interpolate(response[variable], index, following, fraction)) ]
        end
        Row.new(
          time:,
          **values,
          wind_direction: rounded(:wind_direction, direction(response, index, following, fraction)),
          precipitation: rounded(:precipitation, hour_value(response["precipitation"], times, time)),
          weather_code: nearest(response["weather_code"], index, following, fraction)&.round,
          day: daylight?(sample)
        )
      end

      def empty_row(time)
        Row.new(time:, **ROW_KEYS.keys.without(:time).index_with(nil))
      end

      # The sun's altitude at the sample's own hour and cell. Unknown without
      # a cell: the icon then keeps its day variant.
      def daylight?(sample)
        cell = @cells[sample.cell]
        return nil unless cell

        Daylight.day?(time: sample.time, latitude: cell.latitude, longitude: cell.longitude)
      end

      def interpolate(values, index, following, fraction)
        before = Array(values)[index]
        after = Array(values)[following]
        return before if after.nil? || fraction.zero?
        return nil if before.nil?

        before + (after - before) * fraction
      end

      def nearest(values, index, following, fraction)
        Array(values)[fraction < 0.5 ? index : following] || Array(values)[index]
      end

      # The provider's hourly precipitation is the sum over the preceding
      # hour, so the instant belongs to the first hour stamped at or after it.
      def hour_value(values, times, time)
        index = times.index { |hour| hour >= time }
        index.nil? ? nil : Array(values)[index]
      end

      def direction(response, index, following, fraction)
        components = [ index, following ].map do |position|
          speed = Array(response["wind_speed_10m"])[position]
          degrees = Array(response["wind_direction_10m"])[position]
          next nil if speed.nil? || degrees.nil?

          Wind.components(speed, degrees)
        end
        before, after = components
        return before && Wind.direction(*before) if after.nil? || fraction.zero?
        return nil if before.nil?

        Wind.direction(before[0] + (after[0] - before[0]) * fraction, before[1] + (after[1] - before[1]) * fraction)
      end

      def rounded(attribute, value)
        value&.round(PRECISION.fetch(attribute))
      end
    end
  end
end
