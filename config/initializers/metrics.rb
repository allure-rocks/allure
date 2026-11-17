# frozen_string_literal: true

# Metrics bootstrap (docs/dev/METRICS.md).
#
# yabeda-rails installs its request metrics only when it detects a known
# application server, which leaves consoles, tests, and `bin/jobs` without the
# metrics; installing here is deterministic across every entry point and
# guarded so a server-detected install is never subscribed twice.
#
# The /metrics endpoint itself is served by Allure::Metrics::Endpoint and is
# enabled only while METRICS_TOKEN is set. Its database aggregates are
# collected on scrape (Metrics::Collector) through Metrics::Cache.
Rails.application.config.after_initialize do
  Metrics::Collector.mark_started!
  Yabeda::Rails.config.ignore_actions = %w[Rails::HealthController#show]

  unless Yabeda.groups[:rails]&.respond_to?(:requests_total)
    Yabeda::Rails.install!
  end

  Metrics::Schema.define!
  Yabeda.configure { collect { Metrics::Collector.refresh! } }

  # docs/dev/API.md: REST API requests by the scope the operation needs and
  # the status class. `process_action` wraps rescue_from, so a refusal or a
  # 404 is counted with its final status.
  ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*, payload|
    next unless payload[:controller].to_s.start_with?("Api::Rest::V1::")

    status = payload[:status] || (payload[:exception] ? 500 : nil)
    next unless status

    scope = payload[:request]&.env&.fetch("allure.api_scope", nil) || "any"
    Yabeda.allure.api_requests_total.increment({ scope:, status_class: "#{status.to_i / 100}xx" })
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { component: "api_requests_total" })
  end

  Rails.logger.info("[metrics] /metrics enabled") if Allure::Metrics.enabled?
end
