# frozen_string_literal: true

module Allure
  # Voluntary contributions to the instance operator (docs/dev/FUNDING.md). The
  # master switch is deliberately independent from the checkout links: an
  # operator can keep manual contributions and their badges without offering
  # an online payment page.
  module Funding
    TIERS = %w[coffee beer energy].freeze
    BADGE_COLORS = %w[primary blue teal orange purple slate].freeze

    module_function

    def enabled? = Config.enabled?

    def checkout_link(tier) = Config.checkout_link(tier)

    def checkout_links = Config.checkout_links
  end
end
