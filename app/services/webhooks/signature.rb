# frozen_string_literal: true

module Webhooks
  # Standard Webhooks signing (docs/dev/API.md): HMAC-SHA256 with the
  # Base64-decoded secret over "<id>.<timestamp>.<body>", sent as
  # `v1,<base64>`; several secrets give several space-separated signatures.
  module Signature
    module_function

    def header(secrets, id, timestamp, body)
      Array(secrets).map { "v1,#{sign(it, id, timestamp, body)}" }.join(" ")
    end

    def sign(secret, id, timestamp, body)
      key = Base64.strict_decode64(secret.to_s.delete_prefix(WebhookEndpoint::SECRET_PREFIX))
      Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, "#{id}.#{timestamp}.#{body}"))
    end

    # What a receiver does: true when one of the header's signatures matches.
    def verify?(secret, id, timestamp, body, header)
      expected = sign(secret, id, timestamp, body)
      header.to_s.split.any? do |part|
        version, signature = part.split(",", 2)
        version == "v1" && ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected)
      end
    end
  end
end
