# frozen_string_literal: true

require "uri"

module Federation
  # Signs an outbound GET with a local actor so a restricted peer can
  # authorize the fetch; public resources ignore the signature (PLAN_M5 §8.4).
  # The Host header is derived from the URL authority including a non-default
  # port, exactly like the delivery path.
  class SignedFetcher
    DEFAULT_MEDIA_READ_TIMEOUT = 30
    DEFAULT_MEDIA_TOTAL_TIMEOUT = 45

    def initialize(actor:, client: nil)
      @actor = actor
      @client = client || Transport::Client.new
    end

    def get(url, accept:, max_bytes:, read_timeout: DEFAULT_MEDIA_READ_TIMEOUT,
            total_timeout: DEFAULT_MEDIA_TOTAL_TIMEOUT)
      uri = URI.parse(url.to_s)
      host = Allure::Federation::Authority.domain(uri.to_s)
      raise Transport::SsrfGuard::UnsafeUri, "invalid fetch host" if host.blank?

      headers = Signature::Signer.new(actor: @actor).call(
        method: "GET",
        path: uri.request_uri,
        host:,
        body: "",
        date: Time.current.httpdate
      )
      headers["Accept"] = accept if accept.present?
      @client.get(url, headers:, max_bytes:, read_timeout:, total_timeout:)
    rescue URI::InvalidURIError, URI::InvalidComponentError => error
      raise Transport::SsrfGuard::UnsafeUri, error.message
    end
  end
end
