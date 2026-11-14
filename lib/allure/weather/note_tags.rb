# frozen_string_literal: true

module Allure
  module Weather
    # The weather summary on the wire (PLAN_WEATHER.md §6): a handful of Note
    # tags, each a short comma-separated list of SI numbers. The serializer
    # and the strict parser share this codec, so both ends agree on one shape.
    #
    #   weather_condition      clear | … | thunderstorm
    #   weather_temperature    min,max,apparent      (°C)
    #   weather_temperature_mean mean                (°C; its own tag, so a
    #                                                peer reading the
    #                                                three-value tag keeps it)
    #   weather_humidity       mean                  (%)
    #   weather_precipitation  total                 (mm)
    #   weather_wind           mean,gusts,direction  (m/s, m/s, degrees from)
    #   weather_wind_exposure  head,tail,cross,headwind (shares, m/s)
    #
    # An empty position is an absent value. A malformed tag is dropped; a
    # summary that is not valid as a whole is dropped entirely.
    module NoteTags
      NAMES = %w[
        weather_condition weather_temperature weather_temperature_mean weather_humidity weather_precipitation weather_wind
        weather_wind_exposure weather_day
      ].freeze
      MAX_CONTENT = 120

      module_function

      # Returns `[[name, content], …]` for a stored summary.
      def encode(summary)
        return [] unless Summary.valid?(summary)

        summary = summary.stringify_keys
        exposure = summary["wind_exposure"]
        [
          [ "weather_condition", summary["condition"] ],
          [ "weather_temperature", list(summary, %w[temperature_min temperature_max apparent_temperature], 1) ],
          [ "weather_temperature_mean", number(summary["temperature_mean"], 1) ],
          [ "weather_humidity", number(summary["humidity"], 0) ],
          [ "weather_precipitation", number(summary["precipitation"], 1) ],
          [ "weather_wind", list(summary, %w[wind_speed wind_gusts wind_direction], 1) ],
          [ "weather_wind_exposure", exposure && [ *%w[head tail cross].map { number(exposure[it], 3) }, number(exposure["headwind"], 2) ].join(",") ],
          [ "weather_day", summary["is_day"].nil? ? nil : (summary["is_day"] ? "day" : "night") ]
        ].reject { |_name, content| content.nil? || content.delete(",").empty? }
      end

      # Decodes `{ name => content }` back into a summary, or nil. `warn` is
      # called with a short reason for each refusal.
      def decode(contents, warn: ->(_message) { })
        contents = contents.slice(*NAMES)
        return nil if contents.empty?

        summary = {}
        condition = contents["weather_condition"]
        if condition
          Conditions.valid?(condition.strip) ? summary["condition"] = condition.strip : warn.call("invalid weather condition")
        end
        assign(summary, contents["weather_temperature"], %w[temperature_min temperature_max apparent_temperature], warn)
        assign(summary, contents["weather_temperature_mean"], %w[temperature_mean], warn)
        assign(summary, contents["weather_humidity"], %w[humidity], warn)
        assign(summary, contents["weather_precipitation"], %w[precipitation], warn)
        assign(summary, contents["weather_wind"], %w[wind_speed wind_gusts wind_direction], warn)
        exposure = numbers(contents["weather_wind_exposure"], 4, warn)
        if exposure
          summary["wind_exposure"] = { "head" => exposure[0], "tail" => exposure[1], "cross" => exposure[2],
                                       "headwind" => exposure[3] }.compact
        end
        case contents["weather_day"].to_s.strip.downcase
        when "day" then summary["is_day"] = true
        when "night" then summary["is_day"] = false
        when "" then nil
        else warn.call("invalid weather day")
        end
        summary = summary.compact
        return summary if Summary.valid?(summary)

        warn.call("invalid weather summary")
        nil
      end

      def list(summary, keys, precision)
        keys.map { |key| number(summary[key], precision) }.join(",")
      end

      def number(value, precision)
        value.nil? ? "" : format("%.#{precision}f", value.to_f)
      end

      def assign(summary, content, keys, warn)
        values = numbers(content, keys.length, warn)
        keys.zip(values).each { |key, value| summary[key] = value } if values
      end

      def numbers(content, count, warn)
        return nil if content.nil?

        if !content.is_a?(String) || content.length > MAX_CONTENT
          warn.call("invalid weather value")
          return nil
        end

        parts = content.split(",", -1).map(&:strip)
        unless parts.length == count
          warn.call("invalid weather value")
          return nil
        end

        parts.map do |part|
          next nil if part.empty?

          value = Float(part, exception: false)
          unless value&.finite?
            warn.call("invalid weather value")
            return nil
          end
          value
        end
      end
    end
  end
end
