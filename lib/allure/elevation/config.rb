# frozen_string_literal: true

module Allure
  module Elevation
    # Environment-driven configuration for DEM enrichment. Values are read at
    # call time so an operator can enable, move, or tune the provider without a
    # restart. An unset `ELEVATION_BASE_URL` disables the feature everywhere.
    module Config
      BASE_URL_KEY = "ELEVATION_BASE_URL"
      DEFAULT_DATASET = "mapzen"
      DEFAULT_SAMPLE_METRES = 50.0
      DEFAULT_REQUESTS_PER_SECOND = 5.0
      DEFAULT_MAX_REQUESTS_PER_WORKOUT = 40

      module_function

      def base_url
        value = ENV[BASE_URL_KEY].to_s.strip
        value.empty? ? nil : value
      end

      def configured? = !base_url.nil?

      def dataset
        value = ENV["ELEVATION_DATASET"].to_s.strip
        value.empty? ? DEFAULT_DATASET : value
      end

      def interpolation
        value = ENV["ELEVATION_INTERPOLATION"].to_s.strip
        value.empty? ? OpenTopoData::DEFAULT_INTERPOLATION : value
      end

      def sample_metres = positive_float("ELEVATION_SAMPLE_METRES", DEFAULT_SAMPLE_METRES)

      def requests_per_second = positive_float("ELEVATION_REQUESTS_PER_SECOND", DEFAULT_REQUESTS_PER_SECOND)

      def max_requests_per_workout
        positive_integer("ELEVATION_MAX_REQUESTS_PER_WORKOUT", DEFAULT_MAX_REQUESTS_PER_WORKOUT)
      end

      def client
        OpenTopoData.new(base_url:, dataset:, interpolation:)
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
