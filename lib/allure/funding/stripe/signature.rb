# frozen_string_literal: true

require "openssl"

module Allure
  module Funding
    module Stripe
      # Stripe's `t=…,v1=…` HMAC-SHA256 envelope. Verification covers the exact
      # raw request body and finishes before any JSON is trusted or parsed.
      module Signature
        TOLERANCE_SECONDS = 300
        HEX_SHA256 = /\A\h{64}\z/

        module_function

        def verify!(payload, header, secret:, at: Time.now, tolerance: TOLERANCE_SECONDS)
          parts = header.to_s.split(",").filter_map do |entry|
            key, value = entry.strip.split("=", 2)
            [ key, value ] unless key.to_s.empty? || value.to_s.empty?
          end
          timestamps = parts.select { |key, _value| key == "t" }.map(&:last)
          signatures = parts.select { |key, _value| key == "v1" }.map(&:last)
          timestamp = Integer(timestamps.fetch(0), 10) if timestamps.one?
          unless timestamp && (at.to_i - timestamp).abs <= tolerance && signatures.any?
            raise Providers::VerificationError, "invalid Stripe signature timestamp"
          end

          expected = OpenSSL::HMAC.digest("SHA256", secret.to_s, "#{timestamp}.#{payload}")
          unless signatures.any? { |signature| valid_signature?(signature, expected) }
            raise Providers::VerificationError, "invalid Stripe signature"
          end

          payload
        rescue ArgumentError, TypeError, IndexError
          raise Providers::VerificationError, "malformed Stripe signature"
        end

        def valid_signature?(signature, expected)
          return false unless signature.is_a?(String) && signature.match?(HEX_SHA256)

          actual = [ signature ].pack("H*")
          return false unless actual.bytesize == expected.bytesize

          actual.bytes.zip(expected.bytes).reduce(0) { |difference, (left, right)| difference | (left ^ right) }.zero?
        end
        private_class_method :valid_signature?
      end
    end
  end
end
