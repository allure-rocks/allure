# frozen_string_literal: true

module Webhooks
  # Sends one signed delivery (PLAN_API.md §11.3, §11.4) through the
  # federation client and its SSRF guard: HTTPS only (plain HTTP only on the
  # local ring), private addresses refused and re-resolved at every attempt,
  # no redirect followed, a small response read and thrown away.
  class Transport
    class UnsafeUrl < StandardError; end

    Outcome = Data.define(:status_code, :error) do
      def success? = error.nil? && status_code.to_i.between?(200, 299)
      def gone? = status_code == 410
    end

    READ_TIMEOUT = 10
    TOTAL_TIMEOUT = 15
    MAX_RESPONSE_BYTES = 64.kilobytes

    # Specs swap the DNS lookup (`->(host, port) { [ "203.0.113.10" ] }`).
    class_attribute :resolver, default: nil

    def self.guard = Federation::Transport::SsrfGuard.new(resolver:)

    def self.validate_url!(url)
      guard.validate!(url)
    rescue Federation::Transport::SsrfGuard::UnsafeUri
      raise UnsafeUrl
    end

    def initialize(client: Federation::Transport::Client.new(guard: self.class.guard))
      @client = client
    end

    def deliver(endpoint, event, now: Time.current)
      body = event.body
      timestamp = now.to_i.to_s
      response = @client.post(
        endpoint.url, body:, max_redirects: 0, max_bytes: MAX_RESPONSE_BYTES,
                      read_timeout: READ_TIMEOUT, total_timeout: TOTAL_TIMEOUT,
                      headers: {
                        "Content-Type" => "application/json",
                        "User-Agent" => "Allure-Webhooks/#{Allure::VERSION} (+#{Allure::Federation.config.base_url})",
                        "webhook-id" => event.public_id,
                        "webhook-timestamp" => timestamp,
                        "webhook-signature" => Signature.header(endpoint.signing_secrets(now), event.public_id, timestamp, body)
                      }
      )
      Outcome.new(status_code: response.status, error: (response.status.between?(200, 299) ? nil : "http_status"))
    rescue Federation::Transport::Client::TooManyRedirects, Federation::Transport::Client::UnsafeRedirect
      Outcome.new(status_code: nil, error: "redirect")
    rescue Federation::Transport::Client::ResponseTimeout
      Outcome.new(status_code: nil, error: "timeout")
    rescue Federation::Transport::Client::ResponseTooLarge
      Outcome.new(status_code: nil, error: "response_too_large")
    rescue Federation::Transport::Client::NetworkError
      Outcome.new(status_code: nil, error: "network")
    rescue Federation::Transport::SsrfGuard::UnsafeUri
      Outcome.new(status_code: nil, error: "unsafe_url")
    end
  end
end
