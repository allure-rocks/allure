# frozen_string_literal: true

require "uri"

module Allure
  module Funding
    # Environment-driven funding configuration. Every value is read at call
    # time so request specs and an operator's configuration change observe the
    # same switch without rebuilding application state.
    module Config
      TRUE_VALUES = %w[1 true yes on].freeze
      LINK_KEYS = { "coffee" => "FUNDING_LINK_COFFEE", "beer" => "FUNDING_LINK_BEER", "energy" => "FUNDING_LINK_ENERGY" }.freeze
      STRIPE_LINK_KEYS = Funding::TIERS.to_h { |tier| [ tier, "FUNDING_STRIPE_LINK_#{tier.upcase}" ] }.freeze
      STRIPE_PRICE_KEYS = Funding::TIERS.to_h { |tier| [ tier, "FUNDING_STRIPE_PRICE_#{tier.upcase}" ] }.freeze

      module_function

      def enabled? = TRUE_VALUES.include?(ENV["FUNDING_ENABLED"].to_s.strip.downcase)

      def checkout_links
        Funding::TIERS.index_with { |tier| checkout_link(tier) }.compact
      end

      def checkout_link(tier)
        https_url(ENV[LINK_KEYS.fetch(tier.to_s)]) if Funding::TIERS.include?(tier.to_s)
      end

      def stripe_secret_key
        secret(ENV["FUNDING_STRIPE_SECRET_KEY"], /\Ask_(test|live)_[A-Za-z0-9]+\z/)
      end

      def stripe_webhook_secret
        secret(ENV["FUNDING_STRIPE_WEBHOOK_SECRET"], /\Awhsec_[A-Za-z0-9]+\z/)
      end

      def stripe_checkout_link(tier)
        return unless Funding::TIERS.include?(tier.to_s)

        https_url(ENV[STRIPE_LINK_KEYS.fetch(tier.to_s)])
      end

      def stripe_price(tier)
        return unless Funding::TIERS.include?(tier.to_s)

        value = ENV[STRIPE_PRICE_KEYS.fetch(tier.to_s)].to_s.strip
        value if value.match?(/\Aprice_[A-Za-z0-9_]{1,200}\z/)
      end

      # Only complete link+price pairs can be offered or accepted. A price must
      # identify exactly one tier so a verified invoice is never guessed.
      def stripe_prices
        Funding::TIERS.filter_map do |tier|
          if stripe_checkout_link(tier) && stripe_price(tier)
            [ tier, stripe_price(tier) ]
          end
        end.to_h
      end

      def stripe_tier_for_price(price)
        matches = stripe_prices.select { |_tier, configured| configured == price.to_s }.keys
        matches.one? ? matches.first : nil
      end

      def stripe_prices_unambiguous?
        prices = stripe_prices.values
        prices.uniq.length == prices.length
      end

      def stripe_enabled?
        stripe_secret_key.present? && stripe_webhook_secret.present? && stripe_prices.any? && stripe_prices_unambiguous?
      end

      def https_url(value)
        value = value.to_s.strip
        return if value.empty?

        uri = URI.parse(value)
        uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? ? uri.to_s : nil
      rescue URI::InvalidURIError
        nil
      end
      private_class_method :https_url

      def secret(value, pattern)
        value = value.to_s.strip
        value if value.match?(pattern)
      end
      private_class_method :secret
    end
  end
end
