# frozen_string_literal: true

module Allure
  module Weather
    # The weather of a whole workout in a few figures (docs/dev/WEATHER.md):
    # the only weather a publication may carry. It names no place and no
    # instant; values stay SI (°C, %, mm, m/s, degrees the wind blows from).
    module Summary
      KEYS = %w[
        condition temperature_min temperature_max temperature_mean apparent_temperature humidity
        precipitation wind_speed wind_gusts wind_direction wind_exposure is_day
      ].freeze
      HOUR = 3_600
      # The plausible bounds a stored or received summary must respect
      # (docs/dev/WEATHER.md). Anything outside is refused, never clamped.
      RANGES = {
        "temperature_min" => -90.0..60.0, "temperature_max" => -90.0..60.0, "temperature_mean" => -90.0..60.0,
        "apparent_temperature" => -100.0..70.0, "humidity" => 0.0..100.0, "precipitation" => 0.0..1_000.0,
        "wind_speed" => 0.0..100.0, "wind_gusts" => 0.0..150.0, "wind_direction" => 0.0..360.0
      }.freeze
      EXPOSURE_SHARES = %w[head tail cross].freeze
      HEADWIND_RANGE = -100.0..100.0
      SHARE_TOLERANCE = 0.02

      module_function

      # Whether `hash` is a well-formed summary: known keys only, a known
      # condition, numbers within bounds, and exposure shares summing to one.
      def valid?(hash)
        return false unless hash.is_a?(Hash) && hash.any?
        return false unless hash.keys.all? { |key| KEYS.include?(key.to_s) }

        hash = hash.stringify_keys
        return false unless hash["condition"].nil? || Conditions.valid?(hash["condition"])
        return false unless [ nil, true, false ].include?(hash["is_day"])
        return false unless RANGES.all? { |key, range| hash[key].nil? || (hash[key].is_a?(Numeric) && range.cover?(hash[key])) }
        return false if hash["temperature_min"] && hash["temperature_max"] && hash["temperature_min"] > hash["temperature_max"]
        return false unless mean_within_range?(hash)

        exposure_valid?(hash["wind_exposure"])
      end

      def mean_within_range?(hash)
        mean = hash["temperature_mean"]
        return true if mean.nil?

        (hash["temperature_min"].nil? || mean >= hash["temperature_min"] - 0.05) &&
          (hash["temperature_max"].nil? || mean <= hash["temperature_max"] + 0.05)
      end

      def exposure_valid?(exposure)
        return true if exposure.nil?
        return false unless exposure.is_a?(Hash) && exposure.keys.map(&:to_s).all? { |key| (EXPOSURE_SHARES + [ "headwind" ]).include?(key) }

        exposure = exposure.stringify_keys
        shares = EXPOSURE_SHARES.map { |key| exposure[key] }
        return false unless shares.all? { |share| share.is_a?(Numeric) && (0.0..1.0).cover?(share) }
        return false unless (shares.sum - 1.0).abs <= SHARE_TOLERANCE

        exposure["headwind"].nil? || (exposure["headwind"].is_a?(Numeric) && HEADWIND_RANGE.cover?(exposure["headwind"]))
      end

      def call(rows, exposure)
        rows = Array(rows).select(&:usable?)
        return {} if rows.empty?

        temperatures = rows.map(&:temperature)
        summary = {
          "condition" => Conditions.dominant(rows.map { |row| Conditions.token(row.weather_code) }),
          "temperature_min" => temperatures.min.round(1),
          "temperature_max" => temperatures.max.round(1),
          "temperature_mean" => mean(temperatures).round(1),
          "apparent_temperature" => mean(rows.map(&:apparent_temperature))&.round(1),
          "humidity" => mean(rows.map(&:humidity))&.round,
          "precipitation" => precipitation(rows),
          "wind_speed" => mean(rows.map(&:wind_speed)).round(1),
          "wind_gusts" => rows.filter_map(&:wind_gusts).max&.round(1),
          "wind_direction" => Wind.mean_direction(rows.map { |row| [ row.wind_speed, row.wind_direction ] })&.round
        }
        summary["wind_exposure"] = exposure.to_h.slice("head", "tail", "cross", "headwind") if exposure&.present?
        # The icon's day or night variant over the whole workout: the sun was
        # up for the majority of the samples that know.
        days = rows.map(&:day).compact
        summary["is_day"] = days.count(true) * 2 >= days.length unless days.empty?
        summary
      end

      def mean(values)
        values = values.compact
        values.empty? ? nil : values.sum.to_f / values.length
      end

      # One value per provider hour: several samples inside the same hour
      # share its sum.
      def precipitation(rows)
        by_hour = rows.each_with_object({}) do |row, hours|
          next if row.precipitation.nil?

          hours[(row.time.to_i + HOUR - 1) / HOUR] = row.precipitation
        end
        by_hour.empty? ? nil : by_hour.values.sum.round(1)
      end
    end
  end
end
