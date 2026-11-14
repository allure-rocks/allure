# frozen_string_literal: true

module Notifications
  # Sends one encrypted payload to one push subscription (PLAN_PUSH.md §3.2,
  # §5). The body is encrypted for the device (RFC 8291, `aes128gcm`) and the
  # request signed for the relay (VAPID, RFC 8292) with the `web-push` gem's
  # primitives; the request itself goes through the federation client and its
  # SSRF guard — HTTPS only, private addresses refused, no redirect followed —
  # and only to an origin listed in `PUSH_RELAY_ORIGINS`.
  class PushDelivery
    TTL = 86_400
    URGENCY = "normal"
    JWT_LIFETIME = 12.hours
    READ_TIMEOUT = 10
    TOTAL_TIMEOUT = 15
    MAX_RESPONSE_BYTES = 16.kilobytes

    Outcome = Data.define(:status_code, :error) do
      def success? = error.nil? && status_code.to_i.between?(200, 299)
      # The relay says the device is gone, or the endpoint is bound to another
      # VAPID key (this instance changed its pair): the subscription is
      # deleted, and the settings page registers the device again.
      def gone? = [ 404, 410 ].include?(status_code) || error == "key_mismatch"
      # Worth another attempt later: rate limited, the relay or APNs down, or
      # no answer at all. Any other 4xx is final.
      def retryable? = status_code == 429 || status_code.to_i >= 500 || %w[timeout network].include?(error)
    end

    # Specs swap the DNS lookup like `Webhooks::Transport.resolver`.
    class_attribute :resolver, default: nil

    def self.client = Federation::Transport::Client.new(guard: Federation::Transport::SsrfGuard.new(resolver:))

    def initialize(client: self.class.client)
      @client = client
    end

    def deliver(subscription, plaintext, now: Time.current)
      return Outcome.new(status_code: nil, error: "unsafe_url") unless Allure::Push::Config.relay_origin?(subscription.endpoint)

      body = WebPush::Encryption.encrypt(plaintext, subscription.p256dh, subscription.auth)
      response = @client.post(
        subscription.endpoint, body:, max_redirects: 0, max_bytes: MAX_RESPONSE_BYTES,
                               read_timeout: READ_TIMEOUT, total_timeout: TOTAL_TIMEOUT,
                               headers: {
                                 "Content-Type" => "application/octet-stream",
                                 "Content-Encoding" => "aes128gcm",
                                 "TTL" => TTL.to_s,
                                 "Urgency" => URGENCY,
                                 "Authorization" => self.class.vapid_authorization(subscription.endpoint, now:),
                                 "User-Agent" => "Allure-Push/#{Allure::VERSION} (+#{Allure::Federation.config.base_url})"
                               }
      )
      Outcome.new(status_code: response.status, error: self.class.error_of(response))
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

    # A 403 tells a blocked instance (`forbidden`) from an endpoint bound to
    # another key (`key_mismatch`) by the relay's error code.
    def self.error_of(response)
      return if response.status.between?(200, 299)
      return "http_status" unless response.status == 403

      body = JSON.parse(response.body.to_s)
      body.is_a?(Hash) && body["error"] == "key_mismatch" ? "key_mismatch" : "http_status"
    rescue JSON::ParserError
      "http_status"
    end

    # `vapid t=<JWT>, k=<public key>`: ES256, the audience is the relay's
    # origin with its explicit port (the gem's own header drops the port).
    def self.vapid_authorization(endpoint, now: Time.current)
      key = WebPush::VapidKey.from_keys(Allure::Push::Config.public_key, Allure::Push::Config.private_key)
      claims = {
        aud: Allure::Push::Config.origin_of(endpoint),
        exp: (now + JWT_LIFETIME).to_i,
        sub: Allure::Push::Config.subject
      }
      token = JWT.encode(claims, key.curve, "ES256", { typ: "JWT" })
      "vapid t=#{token}, k=#{Allure::Push::Config.public_key_param}"
    end
  end
end
