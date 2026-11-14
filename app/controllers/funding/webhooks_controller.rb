# frozen_string_literal: true

module Funding
  # Provider callbacks carry no browser session or CSRF token. The provider's
  # own signature is the authentication and is checked against the raw body
  # before any event JSON is trusted. Path parameters avoid reading body params.
  class WebhooksController < ApplicationController
    allow_unauthenticated_access
    skip_forgery_protection

    # Never parse an unbounded body just to log two fields.
    WEBHOOK_LOG_BODY_LIMIT = 100_000

    before_action :require_provider

    # PAY-102: the provider payload is billing data (names, addresses, invoice
    # URLs, checkout references). Rails logs request parameters at INFO before
    # the action runs — and its JSON parse-error path logs the whole raw body at
    # DEBUG — so the parsed body is replaced with a minimal operational envelope
    # (event id and type, format-checked against log injection) before
    # instrumentation builds its payload. `verify!` still reads the untouched
    # raw body; nothing in this controller reads `params`.
    def process(*)
      request.request_parameters = { "webhook" => webhook_log_envelope }
      super
    end

    def create
      notification = @provider.verify!(request)
      Funding::ProcessNotification.call(provider: @provider.slug, notification:) if notification
      head :ok
    rescue Allure::Funding::Providers::VerificationError
      head :unauthorized
    rescue Allure::Funding::Providers::ProviderError
      head :bad_gateway
    end

    private

    def webhook_log_envelope
      raw = request.raw_post
      return { "body" => "omitted" } unless raw.bytesize <= WEBHOOK_LOG_BODY_LIMIT

      event = JSON.parse(raw)
      return { "body" => "unparsable" } unless event.is_a?(Hash)

      { "id" => log_safe(event["id"]), "type" => log_safe(event["type"]) }
    rescue JSON::ParserError
      { "body" => "unparsable" }
    end

    def log_safe(value)
      value if value.is_a?(String) && value.match?(/\A[A-Za-z0-9_.:-]{1,200}\z/)
    end

    def require_provider
      @provider = Allure::Funding::Providers.fetch(request.path_parameters[:provider])
      head :not_found unless @provider
    end
  end
end
