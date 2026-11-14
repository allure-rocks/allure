# frozen_string_literal: true

require "base64"
require "openssl"
require "uri"

module Allure
  module Push
    # Push notification settings (PLAN_PUSH.md §5), read from the environment
    # at call time like `Allure::Metrics::Config`. Push is off — no settings
    # card, no job — until the three VAPID values are set and the key pair is
    # a well-formed P-256 pair. The relay list is the only set of origins the
    # instance ever posts a push to.
    module Config
      DEFAULT_RELAY_ORIGINS = %w[https://push.allure.rocks].freeze
      PUBLIC_KEY_BYTES = 65
      PRIVATE_KEY_BYTES = 32

      module_function

      def public_key = ENV.fetch("VAPID_PUBLIC_KEY", "").strip

      # The public key as the relay and the app expect it: unpadded base64url.
      # Every endpoint is bound to it at registration (PLAN_PUSH.md §3.1).
      def public_key_param
        bytes = decode(public_key)
        bytes ? encode(bytes) : public_key.delete("=")
      end

      def private_key = ENV.fetch("VAPID_PRIVATE_KEY", "").strip

      def subject = ENV.fetch("VAPID_SUBJECT", "").strip

      def enabled?
        public = decode(public_key)
        private = decode(private_key)
        !!(public && private && public.bytesize == PUBLIC_KEY_BYTES && public.getbyte(0) == 4 &&
          private.bytesize == PRIVATE_KEY_BYTES && subject.match?(%r{\A(mailto:\S+|https://\S+)\z}))
      end

      # Normalized origins (`scheme://host[:port]`, default port dropped). A
      # plain-HTTP relay is only ever accepted outside production, for a local
      # relay during development.
      def relay_origins
        listed = ENV.fetch("PUSH_RELAY_ORIGINS", "").split(",").map(&:strip).reject(&:empty?)
        listed = DEFAULT_RELAY_ORIGINS if listed.empty?
        listed.filter_map { |value| origin_of(value) }.select { |origin| origin.start_with?("https://") || insecure_allowed? }.uniq
      end

      def relay_origin?(url)
        origin = origin_of(url)
        !origin.nil? && relay_origins.include?(origin)
      end

      # The origin of an absolute http(s) URL without credentials, or nil.
      def origin_of(url)
        uri = URI.parse(url.to_s)
        return unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?

        scheme = uri.scheme.downcase
        host = uri.host.downcase
        default_port = scheme == "https" ? 443 : 80
        uri.port == default_port ? "#{scheme}://#{host}" : "#{scheme}://#{host}:#{uri.port}"
      rescue URI::InvalidURIError, URI::InvalidComponentError
        nil
      end

      def insecure_allowed?
        !(defined?(Rails) && Rails.env.production?)
      end

      # A fresh VAPID key pair, base64url without padding, for
      # `bin/rails push:vapid_keys`.
      def generate_key_pair
        key = OpenSSL::PKey::EC.generate("prime256v1")
        {
          public_key: encode(key.public_key.to_octet_string(:uncompressed)),
          private_key: encode(key.private_key.to_s(2).rjust(PRIVATE_KEY_BYTES, "\0"))
        }
      end

      def encode(bytes) = Base64.urlsafe_encode64(bytes, padding: false)

      # Accepts base64url with or without padding; nil when it does not decode.
      def decode(value)
        return if value.to_s.empty?

        text = value.to_s.tr("+/", "-_").delete("=")
        return unless text.match?(/\A[A-Za-z0-9_-]+\z/)

        Base64.urlsafe_decode64(text + ("=" * ((4 - (text.length % 4)) % 4)))
      rescue ArgumentError
        nil
      end
    end
  end
end
