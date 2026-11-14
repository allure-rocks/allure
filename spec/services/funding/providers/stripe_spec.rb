# frozen_string_literal: true

require "rails_helper"

RSpec.describe Funding::Providers::Stripe, :funding, :stripe_funding do
  include ActiveSupport::Testing::TimeHelpers

  include_examples "a funding provider", env: {
    "FUNDING_STRIPE_SECRET_KEY" => StripeFundingHelpers::STRIPE_TEST_SECRET,
    "FUNDING_STRIPE_WEBHOOK_SECRET" => StripeFundingHelpers::STRIPE_TEST_WEBHOOK_SECRET,
    "FUNDING_STRIPE_PRICE_COFFEE" => StripeFundingHelpers::STRIPE_TEST_PRICE,
    "FUNDING_STRIPE_LINK_COFFEE" => StripeFundingHelpers::STRIPE_TEST_LINK
  }

  let(:client) { instance_double(Allure::Funding::Stripe::Client) }
  let(:user) { create(:user) }
  let(:created_at) { Time.utc(2026, 10, 20, 10, 0, 0) }

  before { allow(described_class).to receive(:client).and_return(client) }

  def annual_price(id = StripeFundingHelpers::STRIPE_TEST_PRICE)
    { "id" => id, "recurring" => { "interval" => "year", "interval_count" => 1 } }
  end

  def subscription_payload(status: "active", cancel_at_period_end: false, price: StripeFundingHelpers::STRIPE_TEST_PRICE)
    { "id" => "sub_123", "customer" => "cus_123", "status" => status,
      "cancel_at_period_end" => cancel_at_period_end, "canceled_at" => nil,
      "items" => { "has_more" => false, "data" => [ { "quantity" => 1, "price" => annual_price(price) } ] } }
  end

  def invoice_payload(status: "paid", reason: "subscription_create", price: StripeFundingHelpers::STRIPE_TEST_PRICE)
    { "id" => "in_123", "subscription" => "sub_123", "customer" => "cus_123", "charge" => "ch_123",
      "status" => status, "paid" => true, "paid_out_of_band" => false,
      "collection_method" => "charge_automatically", "billing_reason" => reason,
      "amount_paid" => 100, "amount_remaining" => 0, "total" => 100,
      "currency" => "eur", "created" => created_at.to_i,
      "status_transitions" => { "paid_at" => created_at.to_i + 60 },
      "lines" => { "has_more" => false, "data" => [
        { "type" => "subscription", "proration" => false, "quantity" => 1, "price" => annual_price(price),
          "period" => { "start" => created_at.to_i, "end" => (created_at + 1.year).to_i } }
      ] } }
  end

  def checkout_payload(mode: "subscription", status: "complete", with_reference: true)
    { "id" => "cs_123", "mode" => mode, "status" => status, "subscription" => "sub_123", "customer" => "cus_123",
      "created" => created_at.to_i,
      "client_reference_id" => with_reference ? Funding::Reference.generate(user: user, tier: "coffee") : nil }
  end

  def line_items_payload(price = annual_price())
    { "has_more" => false, "data" => [ { "quantity" => 1, "price" => price } ] }
  end

  def request(payload:, signature:)
    instance_double(ActionDispatch::Request, raw_post: payload, get_header: signature)
  end

  def refund_object(status: "succeeded", amount: 400, id: "re_123")
    { "id" => id, "status" => status, "amount" => amount, "currency" => "eur",
      "charge" => "ch_123", "created" => created_at.to_i }
  end

  def dispute_object(status: "needs_response", amount: 1000, id: "dp_123")
    { "id" => id, "status" => status, "amount" => amount, "currency" => "eur",
      "charge" => "ch_123", "created" => created_at.to_i }
  end

  def charge_object = { "id" => "ch_123", "invoice" => "in_123" }

  it "appends the signed reference to the hosted payment link" do
    url = described_class.checkout_url(tier: "coffee", reference: "abc_def")
    expect(url).to eq("#{StripeFundingHelpers::STRIPE_TEST_LINK}?client_reference_id=abc_def")
    expect(described_class.checkout_url(tier: "beer", reference: "abc")).to be_nil
    expect { described_class.checkout_url(tier: "coffee", reference: "not valid!") }
      .to raise_error(ArgumentError)
  end

  it "rejects an unverifiable webhook before any API call" do
    payload = checkout_payload.to_json
    expect {
      described_class.verify!(request(payload:, signature: stripe_signature(payload + " ")))
    }.to raise_error(Allure::Funding::Providers::VerificationError)
  end

  it "normalizes a completed subscription checkout without granting a contribution" do
    session = checkout_payload
    payload = stripe_event("checkout.session.completed", session)
    expect(client).to receive(:get).with("/v1/checkout/sessions/cs_123").and_return(session)
    expect(client).to receive(:get).with("/v1/checkout/sessions/cs_123/line_items", { "limit" => 100 }).and_return(line_items_payload)
    expect(client).to receive(:get).with("/v1/subscriptions/sub_123").and_return(subscription_payload)

    notification = described_class.verify!(request(payload:, signature: stripe_signature(payload)))
    expect(notification.event).to be_nil
    expect(notification.binding).to have_attributes(subscription_id: "sub_123", customer_id: "cus_123",
                                                    tier: "coffee", created_at: created_at)
    expect(notification.binding.reference).to be_a(String)
    expect(notification.state).to have_attributes(status: "active", tier: "coffee")
  end

  it "normalizes a paid annual invoice through its durable subscription" do
    invoice = invoice_payload
    subscription = subscription_payload
    checkout_list = { "has_more" => false, "data" => [ checkout_payload ] }
    payload = stripe_event("invoice.paid", invoice)
    expect(client).to receive(:get).with("/v1/invoices/in_123").and_return(invoice)
    expect(client).to receive(:get).with("/v1/subscriptions/sub_123").and_return(subscription)
    expect(client).to receive(:get).with("/v1/checkout/sessions", { "subscription" => "sub_123", "limit" => 100 }).and_return(checkout_list)
    expect(client).to receive(:get).with("/v1/checkout/sessions/cs_123").and_return(checkout_payload)
    expect(client).to receive(:get).with("/v1/checkout/sessions/cs_123/line_items", { "limit" => 100 }).and_return(line_items_payload)

    notification = described_class.verify!(request(payload:, signature: stripe_signature(payload)))
    expect(notification.event).to have_attributes(kind: "payment", external_id: "in_123", tier: "coffee",
                                                  subscription_id: "sub_123", period_start: created_at,
                                                  period_end: created_at + 1.year, amount_cents: 100, currency: "EUR")
    expect(notification.state).to have_attributes(subscription_id: "sub_123", status: "active")
  end

  it "records the paid invoice's verified tier, never the original checkout's (PAY-103)" do
    ENV["FUNDING_STRIPE_LINK_ENERGY"] = "https://buy.stripe.com/test_allureenergy"
    ENV["FUNDING_STRIPE_PRICE_ENERGY"] = "price_test_energy"
    energy_reference = travel_to(created_at) { Funding::Reference.generate(user:, tier: "energy") }

    # Original checkout at the energy tier; the subscription and the paid
    # invoice are coffee.
    checkout = checkout_payload.merge("client_reference_id" => energy_reference)
    invoice = invoice_payload(price: StripeFundingHelpers::STRIPE_TEST_PRICE)
    subscription = subscription_payload(price: StripeFundingHelpers::STRIPE_TEST_PRICE)
    checkout_list = { "has_more" => false, "data" => [ checkout ] }
    payload = stripe_event("invoice.paid", invoice)

    expect(client).to receive(:get).with("/v1/invoices/in_123").and_return(invoice)
    expect(client).to receive(:get).with("/v1/subscriptions/sub_123").and_return(subscription)
    expect(client).to receive(:get).with("/v1/checkout/sessions", { "subscription" => "sub_123", "limit" => 100 }).and_return(checkout_list)
    expect(client).to receive(:get).with("/v1/checkout/sessions/cs_123").and_return(checkout)
    expect(client).to receive(:get).with("/v1/checkout/sessions/cs_123/line_items", { "limit" => 100 })
      .and_return(line_items_payload(annual_price("price_test_energy")))

    notification = described_class.verify!(request(payload:, signature: stripe_signature(payload)))

    # The checkout's tier only establishes the durable account association…
    expect(notification.binding).to have_attributes(tier: "energy", reference: energy_reference)
    # …the paid invoice's tier is what the payment event carries.
    expect(notification.event).to have_attributes(kind: "payment", external_id: "in_123", tier: "coffee")
  end

  it "ignores foreign prices, trials, prorations, zero-value and out-of-band invoices" do
    foreign = invoice_payload(price: annual_price("price_other"))
    zero = invoice_payload.merge("amount_paid" => 0)
    out_of_band = invoice_payload.merge("paid_out_of_band" => true)
    trial = invoice_payload(reason: "subscription_update")
    [ foreign, zero, out_of_band, trial ].each do |invoice|
      payload = stripe_event("invoice.paid", invoice)
      expect(client).to receive(:get).with("/v1/invoices/in_123").and_return(invoice)
      expect(described_class.verify!(request(payload:, signature: stripe_signature(payload)))).to be_nil
    end
  end

  it "refreshes management state from subscription and failed-invoice events without granting" do
    subscription = subscription_payload(status: "past_due")
    updated = { "type" => "customer.subscription.updated", "data" => { "object" => { "id" => "sub_123" } } }.to_json
    expect(client).to receive(:get).with("/v1/subscriptions/sub_123").and_return(subscription)
    notification = described_class.verify!(request(payload: updated, signature: stripe_signature(updated)))
    expect(notification.state).to have_attributes(status: "past_due", tier: "coffee")

    invoice = invoice_payload(status: "open", reason: "subscription_cycle")
    failed_payload = { "type" => "invoice.payment_failed", "data" => { "object" => { "id" => "in_123" } } }.to_json
    expect(client).to receive(:get).with("/v1/invoices/in_123").and_return(invoice)
    expect(client).to receive(:get).with("/v1/subscriptions/sub_123").and_return(subscription)
    failed = described_class.verify!(request(payload: failed_payload, signature: stripe_signature(failed_payload)))
    expect(failed.event).to be_nil
    expect(failed.state).to have_attributes(status: "past_due")
  end

  it "reads a portal-scheduled cancellation (cancel_at) as cancellation at period end" do
    # The hosted portal schedules cancellation with cancel_at (a timestamp),
    # leaving the legacy cancel_at_period_end flag false.
    subscription = subscription_payload.merge("cancel_at" => 1_824_651_155, "canceled_at" => 1_793_120_351)
    updated = { "type" => "customer.subscription.updated", "data" => { "object" => { "id" => "sub_123" } } }.to_json
    expect(client).to receive(:get).with("/v1/subscriptions/sub_123").and_return(subscription)
    notification = described_class.verify!(request(payload: updated, signature: stripe_signature(updated)))
    expect(notification.state).to have_attributes(status: "active", cancel_at_period_end: true,
                                                  canceled_at: Time.at(1_793_120_351).utc)
  end

  it "treats a cancel_at-scheduled subscription as already stopping" do
    subscription = create(:funding_subscription, user:, provider: "stripe", external_id: "sub_123", customer_id: "cus_123")
    current = subscription_payload.merge("cancel_at" => 1_824_651_155, "canceled_at" => 1_793_120_351)
    allow(client).to receive(:post_form)
    allow(client).to receive(:delete)
    expect(client).to receive(:get).with("/v1/subscriptions/sub_123").and_return(current)

    state = described_class.cancel(subscription:)
    expect(state).to have_attributes(status: "active", cancel_at_period_end: true)
    expect(client).not_to have_received(:post_form)
    expect(client).not_to have_received(:delete)
  end

  it "fails closed on a 404 the original account cannot explain (PAY-104)" do
    subscription = create(:funding_subscription, user:, provider: "stripe", external_id: "sub_123",
                                              customer_id: "cus_123", tier: "coffee")
    not_found = Allure::Funding::Stripe::Error.new("Stripe API answered HTTP 404", status: 404)
    allow(client).to receive(:get).with("/v1/subscriptions/sub_123").and_raise(not_found)
    # The persisted customer is not retrievable either: the credentials no
    # longer address the original Stripe account.
    allow(client).to receive(:get).with("/v1/customers/cus_123").and_raise(not_found)

    expect { described_class.cancel(subscription:) }.to raise_error(Allure::Funding::Stripe::Error, /404/)
  end

  it "treats a 404 as terminal only when the customer no longer lists the subscription (PAY-104)" do
    subscription = create(:funding_subscription, user:, provider: "stripe", external_id: "sub_123",
                                              customer_id: "cus_123", tier: "coffee")
    not_found = Allure::Funding::Stripe::Error.new("Stripe API answered HTTP 404", status: 404)
    allow(client).to receive(:get).with("/v1/subscriptions/sub_123").and_raise(not_found)
    allow(client).to receive(:get).with("/v1/customers/cus_123").and_return({ "id" => "cus_123" })
    allow(client).to receive(:get).with("/v1/customers/cus_123/subscriptions", { "status" => "all", "limit" => 100 })
      .and_return({ "has_more" => false, "data" => [ { "id" => "sub_other" } ] })

    state = described_class.cancel(subscription:)

    expect(state.status).to eq("canceled")
    expect(state.cancel_at_period_end).to be(false)
    expect(state.canceled_at).to be_present
  end

  it "fails closed when the subscription still appears in the customer's list after a 404 (PAY-104)" do
    subscription = create(:funding_subscription, user:, provider: "stripe", external_id: "sub_123",
                                              customer_id: "cus_123", tier: "coffee")
    not_found = Allure::Funding::Stripe::Error.new("Stripe API answered HTTP 404", status: 404)
    allow(client).to receive(:get).with("/v1/subscriptions/sub_123").and_raise(not_found)
    allow(client).to receive(:get).with("/v1/customers/cus_123").and_return({ "id" => "cus_123" })
    allow(client).to receive(:get).with("/v1/customers/cus_123/subscriptions", { "status" => "all", "limit" => 100 })
      .and_return({ "has_more" => false, "data" => [ { "id" => "sub_123" } ] })

    expect { described_class.cancel(subscription:) }.to raise_error(Allure::Funding::Stripe::Error, /404/)
  end

  it "flags the original invoice from a refund through authenticated read-back" do
    invoice = invoice_payload
    subscription = subscription_payload
    checkout_list = { "has_more" => false, "data" => [ checkout_payload ] }
    refund_payload = { "type" => "charge.refunded", "data" => { "object" => { "id" => "ch_123" } } }.to_json
    expect(client).to receive(:get).with("/v1/charges/ch_123").and_return({ "id" => "ch_123", "invoice" => "in_123" })
    expect(client).to receive(:get).with("/v1/invoices/in_123").and_return(invoice)
    expect(client).to receive(:get).with("/v1/subscriptions/sub_123").and_return(subscription)
    expect(client).to receive(:get).with("/v1/checkout/sessions", { "subscription" => "sub_123", "limit" => 100 }).and_return(checkout_list)
    expect(client).to receive(:get).with("/v1/checkout/sessions/cs_123").and_return(checkout_payload)
    expect(client).to receive(:get).with("/v1/checkout/sessions/cs_123/line_items", { "limit" => 100 }).and_return(line_items_payload)

    notification = described_class.verify!(request(payload: refund_payload, signature: stripe_signature(refund_payload)))
    expect(notification.event).to have_attributes(kind: "refund", external_id: "in_123")
  end

  it "creates a short-lived hosted portal session from the stored customer" do
    expect(client).to receive(:post_form).with("/v1/billing_portal/sessions",
                                               { "customer" => "cus_123", "return_url" => "https://instance.test/funding" })
                                         .and_return({ "url" => "https://billing.stripe.com/p/session/abc" })
    subscription = build_stubbed(:funding_subscription, user: user, provider: "stripe", customer_id: "cus_123")
    expect(described_class.portal_url(subscription:, return_url: "https://instance.test/funding"))
      .to eq("https://billing.stripe.com/p/session/abc")
    expect { described_class.portal_url(subscription: build_stubbed(:funding_subscription, provider: "other"),
                                       return_url: "https://instance.test/funding") }
      .to raise_error(ArgumentError)
  end

  it "normalizes refund events into reversal signals with their own amount (PAY-105)" do
    refund = refund_object(status: "succeeded", amount: 400) # partial refund
    payload = stripe_event("refund.created", refund)
    expect(client).to receive(:get).with("/v1/refunds/re_123").and_return(refund)
    expect(client).to receive(:get).with("/v1/charges/ch_123").and_return(charge_object)

    notification = described_class.verify!(request(payload:, signature: stripe_signature(payload)))

    expect(notification.reversal).to have_attributes(kind: "refund", external_id: "re_123", status: "succeeded",
                                                      amount_cents: 400, currency: "EUR", payment_external_id: "in_123",
                                                      reported_at: created_at)
  end

  it "normalizes refund failures and ignores unsettled refund statuses (PAY-105)" do
    failed = refund_object(status: "failed")
    payload = stripe_event("refund.updated", failed)
    expect(client).to receive(:get).with("/v1/refunds/re_123").and_return(failed)
    expect(client).to receive(:get).with("/v1/charges/ch_123").and_return(charge_object)
    expect(described_class.verify!(request(payload:, signature: stripe_signature(payload)))
      .reversal).to have_attributes(kind: "refund", status: "failed")

    pending = refund_object(status: "pending", id: "re_999")
    pending_payload = stripe_event("refund.created", pending)
    expect(client).to receive(:get).with("/v1/refunds/re_999").and_return(pending)
    expect(described_class.verify!(request(payload: pending_payload, signature: stripe_signature(pending_payload)))).to be_nil
  end

  it "normalizes the dispute lifecycle into bounded outcomes (PAY-105)" do
    [ [ "charge.dispute.created", "needs_response", "open" ],
      [ "charge.dispute.updated", "under_review", "open" ],
      [ "charge.dispute.closed", "won", "won" ],
      [ "charge.dispute.closed", "lost", "lost" ],
      [ "charge.dispute.closed", "charge_refunded", "lost" ] ].each do |type, stripe_status, expected|
      dispute = dispute_object(status: stripe_status)
      payload = stripe_event(type, dispute)
      expect(client).to receive(:get).with("/v1/disputes/dp_123").and_return(dispute)
      expect(client).to receive(:get).with("/v1/charges/ch_123").and_return(charge_object)

      notification = described_class.verify!(request(payload:, signature: stripe_signature(payload)))
      expect(notification.reversal).to have_attributes(kind: "dispute", external_id: "dp_123", status: expected,
                                                        amount_cents: 1000, payment_external_id: "in_123")
    end
  end

  it "recovers paid invoices from the authenticated API" do
    invoice = invoice_payload
    checkout_list = { "has_more" => false, "data" => [ checkout_payload ] }
    expect(client).to receive(:get).with("/v1/invoices", { "status" => "paid", "limit" => 100,
                                                          "created[gte]" => 32.days.ago.to_i })
                                   .and_return({ "has_more" => false, "data" => [ { "id" => "in_123" } ] })
    expect(client).to receive(:get).with("/v1/invoices/in_123").and_return(invoice)
    expect(client).to receive(:get).with("/v1/subscriptions/sub_123").and_return(subscription_payload)
    expect(client).to receive(:get).with("/v1/checkout/sessions", { "subscription" => "sub_123", "limit" => 100 }).and_return(checkout_list)
    expect(client).to receive(:get).with("/v1/checkout/sessions/cs_123").and_return(checkout_payload)
    expect(client).to receive(:get).with("/v1/checkout/sessions/cs_123/line_items", { "limit" => 100 }).and_return(line_items_payload)

    allow(client).to receive(:get).with("/v1/refunds", anything).and_return({ "has_more" => false, "data" => [] })
    allow(client).to receive(:get).with("/v1/disputes", anything).and_return({ "has_more" => false, "data" => [] })

    notifications = []
    processed = described_class.reconcile(since: 32.days.ago) { |notification| notifications << notification }
    expect(processed).to eq(1)
    expect(notifications.sole.event).to have_attributes(kind: "payment", external_id: "in_123")
  end

  it "also recovers refund and dispute state from the authenticated API (PAY-105)" do
    refund = refund_object
    dispute = dispute_object(status: "lost")
    allow(client).to receive(:get).with("/v1/invoices", anything).and_return({ "has_more" => false, "data" => [] })
    allow(client).to receive(:get).with("/v1/refunds", anything).and_return({ "has_more" => false, "data" => [ { "id" => "re_123" } ] })
    allow(client).to receive(:get).with("/v1/disputes", anything).and_return({ "has_more" => false, "data" => [ { "id" => "dp_123" } ] })
    expect(client).to receive(:get).with("/v1/refunds/re_123").and_return(refund)
    expect(client).to receive(:get).with("/v1/disputes/dp_123").and_return(dispute)
    expect(client).to receive(:get).with("/v1/charges/ch_123").and_return(charge_object).twice

    notifications = []
    processed = described_class.reconcile { |notification| notifications << notification }

    expect(processed).to eq(2)
    expect(notifications.filter_map(&:reversal).map { |r| [ r.kind, r.status ] })
      .to contain_exactly([ "refund", "succeeded" ], [ "dispute", "lost" ])
  end
end
