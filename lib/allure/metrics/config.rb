# frozen_string_literal: true

module Allure
  module Metrics
    # Metrics configuration, read from the environment at call time so tests
    # and consoles see changes without a restart (the Allure::Instance
    # pattern). The endpoint is disabled unless a token is configured, so an
    # unconfigured instance never exposes its counters.
    module Config
      module_function

      def token
        ENV.fetch("METRICS_TOKEN", "").strip
      end

      def enabled?
        token.present?
      end
    end
  end
end
