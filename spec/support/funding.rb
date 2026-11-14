# frozen_string_literal: true

# Funding test material (PLAN_FUNDING.md). The `:funding` tag turns the
# feature on with static manual links and isolates every funding variable from
# the developer's own .env — the Stripe keys included, so an automated
# provider never leaks into a manual-link example. The `:stripe_funding` tag
# (spec/support/stripe_funding.rb) adds a valid-looking Stripe configuration
# on top; it is safe in either hook order because it checks the example's
# metadata rather than relying on hook nesting.
FUNDING_STATIC_KEYS = %w[FUNDING_ENABLED FUNDING_LINK_COFFEE FUNDING_LINK_BEER FUNDING_LINK_ENERGY].freeze
FUNDING_STRIPE_KEYS = %w[
  FUNDING_STRIPE_SECRET_KEY FUNDING_STRIPE_WEBHOOK_SECRET
  FUNDING_STRIPE_PRICE_COFFEE FUNDING_STRIPE_PRICE_BEER FUNDING_STRIPE_PRICE_ENERGY
  FUNDING_STRIPE_LINK_COFFEE FUNDING_STRIPE_LINK_BEER FUNDING_STRIPE_LINK_ENERGY
].freeze
FUNDING_KEYS = (FUNDING_STATIC_KEYS + FUNDING_STRIPE_KEYS).freeze

RSpec.configure do |config|
  # The suite never inherits the developer's funding configuration from .env:
  # examples opt in with the :funding / :stripe_funding tags below. dotenv's
  # autorestore re-applies the boot-time environment after every example
  # (Dotenv.save in before(:suite), Dotenv.restore in after), so the cleanup
  # runs once before the suite and again after each example, after that
  # restore (append_after runs after the regular after hooks).
  cleanup = proc { FUNDING_KEYS.each { |key| ENV.delete(key) } }
  config.before(:suite, &cleanup)
  config.append_after(:each, &cleanup)

  config.around(:each, :funding) do |example|
    previous = FUNDING_KEYS.to_h { |key| [ key, ENV[key] ] }
    ENV["FUNDING_ENABLED"] = "true"
    Allure::Funding::TIERS.each do |tier|
      ENV["FUNDING_LINK_#{tier.upcase}"] = "https://payments.example/#{tier}"
    end
    unless example.metadata[:stripe_funding]
      FUNDING_STRIPE_KEYS.each { |key| ENV.delete(key) }
    end
    example.run
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
