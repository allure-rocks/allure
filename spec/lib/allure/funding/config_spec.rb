# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Funding::Config do
  def with_env(values)
    previous = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it "is disabled unless the master switch is explicitly true" do
    with_env("FUNDING_ENABLED" => nil) { expect(described_class).not_to be_enabled }
    with_env("FUNDING_ENABLED" => "false") { expect(described_class).not_to be_enabled }
    with_env("FUNDING_ENABLED" => " YES ") { expect(described_class).to be_enabled }
  end

  it "returns only configured HTTPS checkout links for known tiers" do
    with_env(
      "FUNDING_LINK_COFFEE" => " https://payments.example/coffee?campaign=annual ",
      "FUNDING_LINK_BEER" => "http://payments.example/beer",
      "FUNDING_LINK_ENERGY" => "javascript:alert(1)"
    ) do
      expect(described_class.checkout_links).to eq("coffee" => "https://payments.example/coffee?campaign=annual")
      expect(described_class.checkout_link("unknown")).to be_nil
    end
  end

  it "enables Stripe only with credentials and complete link+price pairs" do
    with_env(
      "FUNDING_STRIPE_SECRET_KEY" => nil, "FUNDING_STRIPE_WEBHOOK_SECRET" => nil,
      "FUNDING_STRIPE_PRICE_COFFEE" => nil, "FUNDING_STRIPE_LINK_COFFEE" => nil
    ) do
      expect(described_class).not_to be_stripe_enabled
    end

    with_env(
      "FUNDING_STRIPE_SECRET_KEY" => "sk_test_example",
      "FUNDING_STRIPE_WEBHOOK_SECRET" => "whsec_example",
      "FUNDING_STRIPE_PRICE_COFFEE" => "price_coffee",
      "FUNDING_STRIPE_LINK_COFFEE" => "https://buy.stripe.com/test_coffee"
    ) do
      expect(described_class).to be_stripe_enabled
      expect(described_class.stripe_prices).to eq("coffee" => "price_coffee")
      expect(described_class.stripe_tier_for_price("price_coffee")).to eq("coffee")
      expect(described_class.stripe_tier_for_price("price_unknown")).to be_nil
    end
  end

  it "refuses malformed Stripe values and prices shared by two tiers" do
    with_env(
      "FUNDING_STRIPE_SECRET_KEY" => "secret", "FUNDING_STRIPE_WEBHOOK_SECRET" => "secret",
      "FUNDING_STRIPE_PRICE_COFFEE" => "not-a-price", "FUNDING_STRIPE_LINK_COFFEE" => "http://buy.stripe.com/x"
    ) do
      expect(described_class).not_to be_stripe_enabled
      expect(described_class.stripe_prices).to be_empty
    end

    with_env(
      "FUNDING_STRIPE_SECRET_KEY" => "sk_test_example", "FUNDING_STRIPE_WEBHOOK_SECRET" => "whsec_example",
      "FUNDING_STRIPE_PRICE_COFFEE" => "price_shared", "FUNDING_STRIPE_LINK_COFFEE" => "https://buy.stripe.com/a",
      "FUNDING_STRIPE_PRICE_ENERGY" => "price_shared", "FUNDING_STRIPE_LINK_ENERGY" => "https://buy.stripe.com/b"
    ) do
      expect(described_class).not_to be_stripe_enabled
      expect(described_class.stripe_tier_for_price("price_shared")).to be_nil
    end
  end
end
