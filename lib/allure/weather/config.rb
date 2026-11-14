# frozen_string_literal: true

require "date"

module Allure
  module Weather
    # Environment-driven configuration for historical weather (PLAN_WEATHER.md
    # §2). Values are read at call time. The feature exists only while
    # `WEATHER_ENABLED` is true; each account must still opt in.
    module Config
      DEFAULT_FORECAST_URL = "https://historical-forecast-api.open-meteo.com"
      DEFAULT_ARCHIVE_URL = "https://archive-api.open-meteo.com"
      DEFAULT_FORECAST_SINCE = Date.new(2022, 1, 1)
      DEFAULT_REQUESTS_PER_SECOND = 2.0
      DEFAULT_MAX_REQUESTS_PER_DAY = 5_000
      TRUE_VALUES = %w[1 true yes on].freeze

      module_function

      def enabled? = TRUE_VALUES.include?(ENV["WEATHER_ENABLED"].to_s.strip.downcase)

      def forecast_url = url("WEATHER_FORECAST_URL", DEFAULT_FORECAST_URL)

      def archive_url = url("WEATHER_ARCHIVE_URL", DEFAULT_ARCHIVE_URL)

      def api_key = ENV["WEATHER_API_KEY"].to_s.strip.presence

      def forecast_since
        Date.iso8601(ENV["WEATHER_FORECAST_SINCE"].to_s.strip)
      rescue Date::Error
        DEFAULT_FORECAST_SINCE
      end

      def requests_per_second = positive_float("WEATHER_REQUESTS_PER_SECOND", DEFAULT_REQUESTS_PER_SECOND)

      def max_requests_per_day = positive_integer("WEATHER_MAX_REQUESTS_PER_DAY", DEFAULT_MAX_REQUESTS_PER_DAY)

      # The endpoint a workout starting at `time` is asked first.
      def endpoint_for(time)
        time.utc.to_date >= forecast_since ? :forecast : :archive
      end

      def base_url_for(endpoint) = endpoint.to_s == "archive" ? archive_url : forecast_url

      def client = OpenMeteo.new(forecast_url:, archive_url:, api_key:)

      def url(key, default)
        value = ENV[key].to_s.strip
        value.empty? ? default : value
      end

      def positive_float(key, default)
        value = Float(ENV[key], exception: false)
        value&.positive? ? value : default
      end

      def positive_integer(key, default)
        value = Integer(ENV[key], exception: false)
        value&.positive? ? value : default
      end
    end
  end
end
