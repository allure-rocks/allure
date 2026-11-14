# frozen_string_literal: true

module Allure
  module Toponyms
    # The only source for the optional owner toponymy provider. Geocoding is an
    # explicit instance opt-in because sampled owner coordinates leave Allure.
    #
    # The defaults suit a shared public Nominatim. An instance with its own
    # provider can raise the instance-wide request budget and run several
    # geocoding jobs at once; each job then paces itself to its share of the
    # budget. The concurrency is read when the job classes load (boot time).
    module Config
      DEFAULT_REQUESTS_PER_SECOND = 10.0
      DEFAULT_CONCURRENCY = 1

      module_function

      def base_url
        ENV["GEOCODING_BASE_URL"].presence
      end

      def configured?
        base_url.present?
      end

      def requests_per_second = positive_float("GEOCODING_REQUESTS_PER_SECOND", DEFAULT_REQUESTS_PER_SECOND)

      def concurrency = positive_integer("GEOCODING_CONCURRENCY", DEFAULT_CONCURRENCY)

      def request_interval = concurrency / requests_per_second

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
