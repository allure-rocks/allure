# frozen_string_literal: true

module Allure
  module Auth
    # Identity providers (docs/dev/AUTH.md). A provider is enabled when all
    # its environment variables are present; the OmniAuth middleware is built
    # from the same answers at boot, so changing them needs a restart. Names
    # are product names and are never translated.
    module Providers
      Provider = Data.define(:name, :label, :issuer)

      NAMES = %w[google apple oidc].freeze
      GOOGLE_ISSUER = "https://accounts.google.com"
      APPLE_ISSUER = "https://appleid.apple.com"
      DEFAULT_OIDC_LABEL = "OpenID Connect"

      module_function

      def enabled = NAMES.filter_map { |name| find(name) }

      def enabled?(name) = find(name).present?

      # The providers the iOS companion offers: App Store guideline 4.8 asks
      # for Sign in with Apple wherever Google is offered (docs/dev/AUTH.md).
      def for_companion
        providers = enabled
        providers.any? { |provider| provider.name == "apple" } ? providers : providers.reject { |provider| provider.name == "google" }
      end

      def find(name)
        case name.to_s
        when "google"
          Provider.new("google", "Google", GOOGLE_ISSUER) if present?(*google_keys)
        when "apple"
          Provider.new("apple", "Apple", APPLE_ISSUER) if present?(*apple_keys)
        when "oidc"
          Provider.new("oidc", oidc_label, value("AUTH_OIDC_ISSUER")) if present?(*oidc_keys)
        end
      end

      # A linked identity keeps its name even after its provider is disabled.
      def label_for(name)
        { "google" => "Google", "apple" => "Apple", "oidc" => oidc_label }.fetch(name.to_s, name.to_s)
      end

      def oidc_label = value("AUTH_OIDC_LABEL") || DEFAULT_OIDC_LABEL

      def oidc_required_acr = value("AUTH_OIDC_REQUIRED_ACR")

      # An authentication method the generic provider must report in the ID
      # token's `amr` (RFC 8176), e.g. `mfa`, for providers whose `acr` never
      # varies (docs/dev/AUTH.md).
      def oidc_required_amr = value("AUTH_OIDC_REQUIRED_AMR")

      # Environment files cannot hold a multi-line PEM; `\n` stands for a newline.
      def apple_private_key = value("AUTH_APPLE_PRIVATE_KEY")&.gsub("\\n", "\n")

      def value(key) = ENV.fetch(key, "").strip.presence

      def google_keys = %w[AUTH_GOOGLE_CLIENT_ID AUTH_GOOGLE_CLIENT_SECRET]
      def apple_keys = %w[AUTH_APPLE_SERVICES_ID AUTH_APPLE_TEAM_ID AUTH_APPLE_KEY_ID AUTH_APPLE_PRIVATE_KEY]
      def oidc_keys = %w[AUTH_OIDC_ISSUER AUTH_OIDC_CLIENT_ID AUTH_OIDC_CLIENT_SECRET]

      def present?(*keys) = keys.all? { |key| value(key) }
    end
  end
end
