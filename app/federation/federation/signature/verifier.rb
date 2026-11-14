# frozen_string_literal: true

require "base64"
require "digest"
require "openssl"
require "time"

module Federation
  module Signature
    class Verifier
      class InvalidSignature < StandardError; end

      CLOCK_SKEW = 5.minutes
      REQUIRED_HEADERS = Allure::Federation::Signature::CanonicalRequest::REQUIRED_HEADERS
      PreparedVerification = Data.define(:signature, :signed_headers, :date, :canonical)
      Verification = Data.define(:key_id, :signed_headers, :date)

      def initialize(now: Time.current)
        @now = now
      end

      def verify_body_digest!(headers:, body: "")
        normalized_headers = headers.to_h.transform_keys { |key| key.to_s.downcase }
        verify_digest!(normalized_headers.fetch("digest"), body.to_s.b)
        true
      rescue KeyError, TypeError => error
        raise InvalidSignature, error.message
      end

      def call(method:, path:, headers:, body: "", public_key:)
        prepared = prepare(method:, path:, headers:, body:)
        verify(prepared:, public_key:)
      end

      def prepare(method:, path:, headers:, body: "")
        normalized_headers = headers.to_h.transform_keys { |key| key.to_s.downcase }
        verify_digest!(normalized_headers.fetch("digest"), body.to_s.b)
        signature = parse_signature(normalized_headers.fetch("signature"))
        signed_headers = signature.fetch("headers").split.map(&:downcase)
        validate_signed_headers!(signed_headers)
        date = parse_date(normalized_headers.fetch("date"))
        verify_clock_skew!(date)

        canonical = Allure::Federation::Signature::CanonicalRequest.new(
          method:, path:, headers: normalized_headers, signed_headers:
        ).call
        PreparedVerification.new(signature:, signed_headers:, date:, canonical:)
      rescue KeyError, ArgumentError, TypeError => error
        raise InvalidSignature, error.message
      end

      def verify(prepared:, public_key:)
        key = public_key.is_a?(OpenSSL::PKey::PKey) ? public_key : OpenSSL::PKey.read(public_key.to_s)
        signature_bytes = Base64.strict_decode64(prepared.signature.fetch("signature"))
        verified = key.verify(OpenSSL::Digest::SHA256.new, signature_bytes, prepared.canonical)
        raise InvalidSignature, "signature verification failed" unless verified

        Verification.new(prepared.signature.fetch("keyid"), prepared.signed_headers, prepared.date)
      rescue KeyError, ArgumentError, OpenSSL::PKey::PKeyError, TypeError => error
        raise InvalidSignature, error.message
      end

      private

      def parse_signature(header)
        values = header.to_s.split(",").to_h do |part|
          name, value = part.strip.split("=", 2)
          raise InvalidSignature, "malformed signature parameter" unless name.present? && value.present?

          [ name.downcase, unquote(value) ]
        end
        required = %w[keyid algorithm headers signature]
        raise InvalidSignature, "signature parameter is missing" unless required.all? { values.key?(_1) }
        raise InvalidSignature, "unsupported signature algorithm" unless values["algorithm"] == "rsa-sha256"

        values
      end

      def unquote(value)
        value = value.strip
        return value[1...-1] if value.start_with?("\"") && value.end_with?("\"") && value.length >= 2

        raise InvalidSignature, "signature parameter must be quoted"
      end

      def validate_signed_headers!(signed_headers)
        raise InvalidSignature, "signed headers must be unique" unless signed_headers.uniq == signed_headers
        return if REQUIRED_HEADERS.all? { signed_headers.include?(_1) }

        raise InvalidSignature, "required header is not signed"
      end

      def verify_digest!(header, body)
        expected = "SHA-256=#{Base64.strict_encode64(Digest::SHA256.digest(body))}"
        raise InvalidSignature, "body digest mismatch" unless ActiveSupport::SecurityUtils.secure_compare(header.to_s, expected)
      rescue ArgumentError
        raise InvalidSignature, "body digest mismatch"
      end

      def parse_date(value)
        Time.httpdate(value.to_s)
      rescue ArgumentError
        raise InvalidSignature, "invalid date"
      end

      def verify_clock_skew!(date)
        raise InvalidSignature, "date is outside the clock-skew window" if (date - @now).abs > CLOCK_SKEW
      end
    end
  end
end
