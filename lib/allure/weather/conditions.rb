# frozen_string_literal: true

module Allure
  module Weather
    # WMO weather interpretation codes → Allure's condition tokens
    # (PLAN_WEATHER.md §3). The token is the wire and storage value; the icon
    # is presentation only.
    module Conditions
      TOKENS = %w[
        clear mostly_clear partly_cloudy overcast fog drizzle rain heavy_rain
        freezing_rain snow showers thunderstorm
      ].freeze

      CODES = {
        0 => "clear", 1 => "mostly_clear", 2 => "partly_cloudy", 3 => "overcast",
        45 => "fog", 48 => "fog",
        51 => "drizzle", 53 => "drizzle", 55 => "drizzle",
        56 => "freezing_rain", 57 => "freezing_rain",
        61 => "rain", 63 => "rain", 65 => "heavy_rain",
        66 => "freezing_rain", 67 => "freezing_rain",
        71 => "snow", 73 => "snow", 75 => "snow", 77 => "snow", 85 => "snow", 86 => "snow",
        80 => "showers", 81 => "showers", 82 => "heavy_rain",
        95 => "thunderstorm", 96 => "thunderstorm", 99 => "thunderstorm"
      }.freeze

      # The most significant condition wins a tie-free "dominant" choice:
      # precipitation and storms outrank sky cover.
      SEVERITY = TOKENS.each_with_index.to_h.freeze

      module_function

      def token(code)
        return nil if code.nil?

        CODES[Integer(code, exception: false)]
      end

      def valid?(token) = TOKENS.include?(token)

      # The dominant condition over a series: the most frequent, ties broken
      # by severity; a condition covering at least a quarter of the samples
      # and more severe than the most frequent one wins (a shower in an
      # otherwise cloudy ride is what the athlete remembers).
      def dominant(tokens)
        tokens = tokens.compact
        return nil if tokens.empty?

        counts = tokens.tally
        frequent = counts.max_by { |token, count| [ count, SEVERITY.fetch(token, 0) ] }.first
        severe = counts.select { |_token, count| count * 4 >= tokens.length }
                       .max_by { |token, _count| SEVERITY.fetch(token, 0) }&.first
        severe && SEVERITY.fetch(severe, 0) > SEVERITY.fetch(frequent, 0) && precipitating?(severe) ? severe : frequent
      end

      def precipitating?(token) = SEVERITY.fetch(token, 0) >= SEVERITY.fetch("drizzle")
    end
  end
end
