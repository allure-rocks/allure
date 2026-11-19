# frozen_string_literal: true

require "json"

module Allure
  module Assistant
    # Environment-driven configuration for the assistant (docs/dev/AI.md).
    # Values are read at call time, so an operator can point the instance at
    # another model, key or budget without a restart. The feature exists only
    # while both AI_BASE_URL and AI_MODEL are set; each account must still opt
    # in.
    module Config
      BASE_URL_KEY = "AI_BASE_URL"
      MODEL_KEY = "AI_MODEL"
      DEFAULT_TIMEOUT = 300
      DEFAULT_MAX_REQUESTS_PER_DAY = 500

      module_function

      def base_url
        value = ENV[BASE_URL_KEY].to_s.strip
        value.empty? ? nil : value
      end

      def model
        value = ENV[MODEL_KEY].to_s.strip
        value.empty? ? nil : value
      end

      def api_key
        value = ENV["AI_API_KEY"].to_s.strip
        value.empty? ? nil : value
      end

      # A JSON object merged into every request body (AI.md §2). A malformed
      # value is ignored instead of breaking every generation: the operator
      # then sees the model's own behaviour and fixes the variable.
      def request_options
        value = ENV["AI_REQUEST_OPTIONS"].to_s.strip
        return {} if value.empty?

        parsed = JSON.parse(value)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def timeout = positive_integer("AI_TIMEOUT", DEFAULT_TIMEOUT)

      def max_requests_per_day = positive_integer("AI_MAX_REQUESTS_PER_DAY", DEFAULT_MAX_REQUESTS_PER_DAY)

      def enabled? = !base_url.nil? && !model.nil?

      def client
        Client.new(base_url:, model:, api_key:, request_options:, timeout:)
      end

      def positive_integer(key, default)
        value = Integer(ENV[key], exception: false)
        value&.positive? ? value : default
      end
    end
  end
end
