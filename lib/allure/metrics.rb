# frozen_string_literal: true

module Allure
  # The metrics boundary (PLAN_METRICS.md): a Prometheus text endpoint for
  # Grafana, mounted at /metrics and served only while METRICS_TOKEN is set.
  #
  # Metric names, label vocabularies, and the privacy negatives are the stable
  # interface documented in PLAN_METRICS.md. Metric values are aggregated
  # counts and bounded enums only: never coordinates, payloads, keys, remote
  # HTML, domains, actor URIs, usernames, or short IDs.
  module Metrics
    module_function

    def enabled? = Config.enabled?
    def token = Config.token
  end
end
