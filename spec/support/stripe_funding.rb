# frozen_string_literal: true

require "openssl"

# Stripe test material for the funding suite. The values are dummies; they
# never leave the test process. Use the `:stripe_funding` tag to configure a
# valid-looking coffee-tier provider.
module StripeFundingHelpers
  STRIPE_TEST_SECRET = "sk_test_alluredevtest"
  STRIPE_TEST_WEBHOOK_SECRET = "whsec_alluredevtest"
  STRIPE_TEST_PRICE = "price_test_coffee"
  STRIPE_TEST_LINK = "https://buy.stripe.com/test_allurecoffee"

  def stripe_signature(payload, secret: StripeFundingHelpers::STRIPE_TEST_WEBHOOK_SECRET, at: Time.current)
    timestamp = at.to_i
    "t=#{timestamp},v1=#{OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")}"
  end

  def stub_stripe(path, response:, method: :get, status: 200, query: nil)
    url = "https://api.stripe.com#{path}"
    url = "#{url}?#{URI.encode_www_form(query)}" if query && method == :get
    stub_request(method, url).to_return(
      status:, headers: { "Content-Type" => "application/json" }, body: response.to_json
    )
  end

  def stripe_annual_price(id = StripeFundingHelpers::STRIPE_TEST_PRICE)
    { "id" => id, "recurring" => { "interval" => "year", "interval_count" => 1 } }
  end

  def stripe_subscription(status: "active", cancel_at_period_end: false, price: StripeFundingHelpers::STRIPE_TEST_PRICE)
    { "id" => "sub_123", "customer" => "cus_123", "status" => status,
      "cancel_at_period_end" => cancel_at_period_end, "canceled_at" => nil,
      "items" => { "has_more" => false, "data" => [ { "quantity" => 1, "price" => stripe_annual_price(price) } ] } }
  end

  def stripe_invoice(created_at: STRIPE_TEST_CREATED_AT.to_i, status: "paid",
                     reason: "subscription_create", price: STRIPE_TEST_PRICE, amount: 100)
    { "id" => "in_123", "subscription" => "sub_123", "customer" => "cus_123", "charge" => "ch_123",
      "status" => status, "paid" => true, "paid_out_of_band" => false,
      "collection_method" => "charge_automatically", "billing_reason" => reason,
      "amount_paid" => amount, "amount_remaining" => 0, "total" => amount, "currency" => "eur",
      "created" => created_at, "status_transitions" => { "paid_at" => created_at + 60 },
      "lines" => { "has_more" => false, "data" => [
        { "type" => "subscription", "proration" => false, "quantity" => 1, "price" => stripe_annual_price(price),
          "period" => { "start" => created_at, "end" => (Time.at(created_at) + 1.year).to_i } }
      ] } }
  end

  def stripe_checkout(user, created_at: STRIPE_TEST_CREATED_AT.to_i, with_reference: true)
    { "id" => "cs_123", "mode" => "subscription", "status" => "complete", "subscription" => "sub_123",
      "customer" => "cus_123", "created" => created_at,
      "client_reference_id" => with_reference ? Funding::Reference.generate(user:, tier: "coffee") : nil }
  end

  def stripe_line_items(price = StripeFundingHelpers::STRIPE_TEST_PRICE)
    { "has_more" => false, "data" => [ { "quantity" => 1, "price" => stripe_annual_price(price) } ] }
  end

  def stripe_event(type, object)
    { "type" => type, "data" => { "object" => object } }.to_json
  end

  STRIPE_TEST_CREATED_AT = Time.utc(2026, 10, 20, 10, 0, 0)
end

RSpec.configure do |config|
  config.include StripeFundingHelpers, :stripe_funding

  config.around(:each, :stripe_funding) do |example|
    keys = %w[FUNDING_ENABLED FUNDING_STRIPE_SECRET_KEY FUNDING_STRIPE_WEBHOOK_SECRET
              FUNDING_STRIPE_PRICE_COFFEE FUNDING_STRIPE_PRICE_BEER FUNDING_STRIPE_PRICE_ENERGY
              FUNDING_STRIPE_LINK_COFFEE FUNDING_STRIPE_LINK_BEER FUNDING_STRIPE_LINK_ENERGY
              FUNDING_LINK_COFFEE FUNDING_LINK_BEER FUNDING_LINK_ENERGY]
    previous = keys.to_h { |key| [ key, ENV[key] ] }
    ENV["FUNDING_ENABLED"] = "true"
    ENV["FUNDING_STRIPE_SECRET_KEY"] = StripeFundingHelpers::STRIPE_TEST_SECRET
    ENV["FUNDING_STRIPE_WEBHOOK_SECRET"] = StripeFundingHelpers::STRIPE_TEST_WEBHOOK_SECRET
    ENV["FUNDING_STRIPE_PRICE_COFFEE"] = StripeFundingHelpers::STRIPE_TEST_PRICE
    ENV["FUNDING_STRIPE_LINK_COFFEE"] = StripeFundingHelpers::STRIPE_TEST_LINK
    example.run
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
