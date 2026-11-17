# frozen_string_literal: true

require "base64"
require "digest"
require "openssl"

module Federation
  module Signature
    class Signer
      class InvalidActor < StandardError; end

      CORE_HEADERS = %w[(request-target) host date digest].freeze

      def initialize(actor:)
        @actor = actor
      end

      def call(method:, path:, host:, body: "", content_type: nil, date: Time.current.httpdate)
        validate_actor!

        digest = "SHA-256=#{Base64.strict_encode64(Digest::SHA256.digest(body.to_s.b))}"
        signed_headers = CORE_HEADERS.dup
        signed_headers << "content-type" if content_type.present?
        headers = {
          "host" => host,
          "date" => date,
          "digest" => digest
        }
        headers["content-type"] = content_type if content_type.present?
        canonical = Allure::Federation::Signature::CanonicalRequest.new(
          method:, path:, headers:, signed_headers:
        ).call
        signature = private_key.sign(OpenSSL::Digest::SHA256.new, canonical)

        {
          "Host" => host,
          "Date" => date,
          "Digest" => digest,
          "Signature" => signature_header(signed_headers, signature)
        }.tap do |result|
          result["Content-Type"] = content_type if content_type.present?
        end
      rescue OpenSSL::PKey::PKeyError, ArgumentError => error
        raise InvalidActor, error.message
      end

      private

      # A tombstoned actor must still be able to sign its own withdrawal: the
      # account Delete is created while the actor is current and delivered
      # after tombstoning, before the key retirement sweep destroys the key
      # (docs/dev/FEDERATION.md).
      def validate_actor!
        return if @actor.is_a?(Actor) && @actor.local? && signable?

        raise InvalidActor, "a current local actor is required"
      end

      def signable?
        return true unless @actor.tombstoned?

        @actor.private_key_ciphertext.present? && @actor.private_key_retired_at.blank?
      end

      def private_key
        key = OpenSSL::PKey.read(@actor.private_key_ciphertext.to_s)
        raise InvalidActor, "local actor has no private key" unless key.private?

        key
      end

      def signature_header(signed_headers, signature)
        %(keyId="#{@actor.public_key_id}",algorithm="rsa-sha256",headers="#{signed_headers.join(" ")}",signature="#{Base64.strict_encode64(signature)}")
      end
    end
  end
end
