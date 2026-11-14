# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Funding provider webhooks", :funding, :stripe_funding do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user) }
  let(:created_at) { Time.utc(2026, 10, 20, 10, 0, 0) }
  let(:invoice) { stripe_invoice(created_at: created_at.to_i) }
  let(:subscription) { stripe_subscription }
  let(:checkout) { stripe_checkout(user, created_at: created_at.to_i) }

  def post_webhook(payload, signature: stripe_signature(payload))
    post funding_webhook_path("stripe"), params: payload,
      headers: { "Content-Type" => "application/json", "Stripe-Signature" => signature }
  end

  def stub_binding_apis(invoice:, subscription:, checkout: stripe_checkout(user, created_at: created_at.to_i))
    stub_stripe("/v1/invoices/in_123", response: invoice)
    stub_stripe("/v1/subscriptions/sub_123", response: subscription)
    stub_stripe("/v1/checkout/sessions", response: { "has_more" => false, "data" => [ checkout ] },
                query: { "subscription" => "sub_123", "limit" => 100 })
    stub_stripe("/v1/checkout/sessions/cs_123", response: checkout)
    stub_stripe("/v1/checkout/sessions/cs_123/line_items", response: stripe_line_items,
                query: { "limit" => 100 })
  end

  it "binds a completed checkout without granting a contribution" do
    session = stripe_checkout(user, created_at: Time.current.to_i)
    stub_stripe("/v1/checkout/sessions/cs_123", response: session)
    stub_stripe("/v1/checkout/sessions/cs_123/line_items", response: stripe_line_items, query: { "limit" => 100 })
    stub_stripe("/v1/subscriptions/sub_123", response: subscription)

    post_webhook(stripe_event("checkout.session.completed", { "id" => "cs_123" }))
    expect(response).to have_http_status(:ok)
    subscription_row = FundingSubscription.sole
    expect(subscription_row).to have_attributes(user:, provider: "stripe", customer_id: "cus_123", status: "active")
    expect(FundingContribution.count).to eq(0)
  end

  it "records the first paid invoice through the verified reference and ignores redelivery" do
    reference = travel_to(created_at) { Funding::Reference.generate(user:, tier: "coffee") }
    checkout = stripe_checkout(user, created_at: created_at.to_i).merge("client_reference_id" => reference)
    stub_binding_apis(invoice:, subscription:, checkout:)

    post_webhook(stripe_event("invoice.paid", { "id" => "in_123" }))
    expect(response).to have_http_status(:ok)
    contribution = FundingContribution.sole
    expect(contribution).to have_attributes(user:, provider: "stripe", tier: "coffee",
                                            starts_at: Time.at(created_at), expires_at: Time.at(created_at) + 1.year)
    expect(user.notifications.where(kind: "funding_recorded").count).to eq(1)

    post_webhook(stripe_event("invoice.paid", { "id" => "in_123" }))
    expect(FundingContribution.count).to eq(1)
    expect(user.notifications.where(kind: "funding_recorded").count).to eq(1)
  end

  it "records the paid invoice's tier, never the original checkout's (PAY-103)" do
    ENV["FUNDING_STRIPE_LINK_ENERGY"] = "https://buy.stripe.com/test_allureenergy"
    ENV["FUNDING_STRIPE_PRICE_ENERGY"] = "price_test_energy"
    reference = travel_to(created_at) { Funding::Reference.generate(user:, tier: "energy") }

    # The checkout was completed at the energy tier; the subscription and the
    # paid invoice are coffee (a downgraded plan).
    checkout = stripe_checkout(user, created_at: created_at.to_i).merge("client_reference_id" => reference)
    energy_line_items = { "has_more" => false, "data" => [ { "quantity" => 1,
                                                            "price" => stripe_annual_price("price_test_energy") } ] }
    stub_stripe("/v1/invoices/in_123", response: invoice)
    stub_stripe("/v1/subscriptions/sub_123", response: subscription)
    stub_stripe("/v1/checkout/sessions", response: { "has_more" => false, "data" => [ checkout ] },
                query: { "subscription" => "sub_123", "limit" => 100 })
    stub_stripe("/v1/checkout/sessions/cs_123", response: checkout)
    stub_stripe("/v1/checkout/sessions/cs_123/line_items", response: energy_line_items, query: { "limit" => 100 })

    post_webhook(stripe_event("invoice.paid", { "id" => "in_123" }))
    expect(response).to have_http_status(:ok)

    expect(FundingSubscription.sole.user).to eq(user)
    expect(FundingContribution.sole).to have_attributes(user:, tier: "coffee")
    expect(user.reload.funding_badge_tier).to eq("coffee")
  end

  def record_paid_invoice!
    reference = travel_to(created_at) { Funding::Reference.generate(user:, tier: "coffee") }
    checkout = stripe_checkout(user, created_at: created_at.to_i).merge("client_reference_id" => reference)
    stub_binding_apis(invoice:, subscription:, checkout:)
    post_webhook(stripe_event("invoice.paid", { "id" => "in_123" }))
    expect(response).to have_http_status(:ok)
    FundingContribution.sole
  end

  it "records a signed dispute as a durable operator-visible reversal, updating its outcome in place (PAY-105)" do
    contribution = record_paid_invoice!
    dispute = { "id" => "dp_1", "status" => "needs_response", "amount" => 100, "currency" => "eur",
                "charge" => "ch_123", "created" => created_at.to_i }
    stub_stripe("/v1/disputes/dp_1", response: dispute)
    stub_stripe("/v1/charges/ch_123", response: { "id" => "ch_123", "invoice" => "in_123" })

    post_webhook(stripe_event("charge.dispute.created", dispute))
    expect(response).to have_http_status(:ok)
    expect(contribution.funding_reversals.sole).to have_attributes(kind: "dispute", external_id: "dp_1",
                                                                   status: "open", amount_cents: 100, currency: "EUR")

    stub_stripe("/v1/disputes/dp_1", response: dispute.merge("status" => "lost"))
    post_webhook(stripe_event("charge.dispute.closed", dispute.merge("status" => "lost")))
    expect(response).to have_http_status(:ok)

    expect(contribution.funding_reversals.sole.status).to eq("lost")
    # The original payment is never rewritten; the badge-after-refund policy is unchanged.
    expect(contribution.reload).to have_attributes(status: "active", metadata: {})
  end

  it "records partial refunds and refund failures idempotently (PAY-105)" do
    contribution = record_paid_invoice!
    refund = { "id" => "re_1", "status" => "succeeded", "amount" => 40, "currency" => "eur",
               "charge" => "ch_123", "created" => created_at.to_i }
    stub_stripe("/v1/refunds/re_1", response: refund)
    stub_stripe("/v1/charges/ch_123", response: { "id" => "ch_123", "invoice" => "in_123" })

    2.times { post_webhook(stripe_event("refund.created", refund)) }
    expect(response).to have_http_status(:ok)
    expect(contribution.funding_reversals.sole).to have_attributes(kind: "refund", status: "succeeded", amount_cents: 40)

    failed = refund.merge("id" => "re_2", "status" => "failed")
    stub_stripe("/v1/refunds/re_2", response: failed)
    post_webhook(stripe_event("refund.updated", failed))
    expect(response).to have_http_status(:ok)
    expect(contribution.funding_reversals.order(:external_id).pluck(:status)).to eq(%w[succeeded failed])
  end

  it "rejects a forged signature before reading the event or calling the API" do
    payload = stripe_event("invoice.paid", { "id" => "in_123" })
    post_webhook(payload, signature: stripe_signature(payload + " "))
    expect(response).to have_http_status(:unauthorized)
    expect(FundingSubscription.count).to eq(0)
    expect(FundingContribution.count).to eq(0)
  end

  it "answers 404 for an unknown provider and while the provider is disabled" do
    post funding_webhook_path("helloasso"), params: "{}", headers: { "Stripe-Signature" => "t=1,v1=#{"a" * 64}" }
    expect(response).to have_http_status(:not_found)

    ENV["FUNDING_STRIPE_WEBHOOK_SECRET"] = nil
    post funding_webhook_path("stripe"), params: "{}", headers: { "Stripe-Signature" => "t=1,v1=#{"a" * 64}" }
    expect(response).to have_http_status(:not_found)
    expect(FundingContribution.count).to eq(0)
  end

  it "leaves an expired checkout reference unmatched and attachable by the operator" do
    reference = travel_to(created_at - 1.hour) { Funding::Reference.generate(user:, tier: "coffee") }
    checkout = stripe_checkout(user, created_at: created_at.to_i + 3.hours).merge("client_reference_id" => reference)
    stub_binding_apis(invoice:, subscription:, checkout:)

    post_webhook(stripe_event("invoice.paid", { "id" => "in_123" }))
    expect(response).to have_http_status(:ok)
    expect(FundingSubscription.sole.user).to be_nil
    expect(FundingContribution.sole.user).to be_nil
  end

  it "ignores foreign prices, trials and prorations" do
    invoice = stripe_invoice(price: "price_foreign")
    subscription = stripe_subscription(price: "price_foreign")
    checkout = stripe_checkout(user).merge("client_reference_id" => nil)
    stub_binding_apis(invoice:, subscription:, checkout:)

    post_webhook(stripe_event("invoice.paid", { "id" => "in_123" }))
    expect(response).to have_http_status(:ok)
    expect(FundingSubscription.count).to eq(0)
    expect(FundingContribution.count).to eq(0)
  end

  it "refreshes a canceled subscription without touching paid periods" do
    subscription = create(:funding_subscription, user:, provider: "stripe", external_id: "sub_123", customer_id: "cus_123", tier: "coffee")
    contribution = create(:funding_contribution, :subscription, funding_subscription: subscription)
    subscription_payload = stripe_subscription(status: "canceled", cancel_at_period_end: false, price: StripeFundingHelpers::STRIPE_TEST_PRICE)
    stub_stripe("/v1/subscriptions/sub_123", response: subscription_payload)

    post_webhook(stripe_event("customer.subscription.deleted", { "id" => "sub_123" }))
    expect(response).to have_http_status(:ok)
    expect(subscription.reload).to have_attributes(status: "canceled", cancel_at_period_end: false)
    expect(contribution.reload).not_to be_revoked
  end

  describe "payload redaction (PAY-102)" do
    # ActionController::LogSubscriber reads ActionController::Base.logger.
    def capture_controller_log
      io = StringIO.new
      previous = ActionController::Base.logger
      ActionController::Base.logger = ActiveSupport::Logger.new(io)
      yield
      io.string
    ensure
      ActionController::Base.logger = previous
    end

    it "logs only a minimal envelope — never billing data — for valid and forged requests" do
      reference = travel_to(created_at) { Funding::Reference.generate(user:, tier: "coffee") }
      checkout = stripe_checkout(user, created_at: created_at.to_i).merge("client_reference_id" => reference)
      stub_binding_apis(invoice:, subscription:, checkout:)

      billing_object = {
        "id" => "in_123",
        "type" => "invoice",
        # Not matched by any filter pattern: only the controller's envelope
        # replacement keeps it out of the log.
        "custom_note" => "Marie Curie, 1 Rue de la Paix, 75001",
        "client_reference_id" => reference,
        "customer" => "cus_123",
        "charge" => "ch_123",
        "customer_details" => {
          "name" => "Marie Curie", "email" => "marie.curie@example.test",
          "address" => { "line1" => "1 Rue de la Paix", "city" => "Paris", "postal_code" => "75001", "country" => "FR" }
        },
        "billing_details" => { "name" => "Marie Curie", "address" => { "line1" => "1 Rue de la Paix" } },
        "hosted_invoice_url" => "https://invoice.stripe.com/i/acct_test/secret",
        "invoice_pdf" => "https://pay.stripe.com/invoice/acct_test/secret_pdf"
      }

      event = { "id" => "evt_123", "type" => "invoice.paid", "data" => { "object" => billing_object } }.to_json

      log = capture_controller_log do
        post_webhook(event)
        expect(response).to have_http_status(:ok)

        post_webhook(event, signature: stripe_signature("forged"))
        expect(response).to have_http_status(:unauthorized)
      end

      # The operational envelope survives: event id, type, provider, result.
      expect(log).to include('"webhook" => {"id" => "evt_123", "type" => "invoice.paid"}')
      expect(log).to include("Completed 200")
      expect(log).to include("Completed 401")

      # Nothing billing-related may appear, on either request.
      expect(log).not_to include(reference)
      [ "Marie Curie", "marie.curie@example.test", "Rue de la Paix", "75001", "Paris",
        "invoice.stripe.com", "pay.stripe.com", "cus_123", "ch_123",
        "client_reference_id", "hosted_invoice_url", "invoice_pdf",
        "billing_details", "customer_details" ].each do |secret|
        expect(log).not_to include(secret)
      end
    end

    it "logs only an unparsable marker for a malformed or non-object body" do
      log = capture_controller_log do
        post funding_webhook_path("stripe"), params: "{not json",
          headers: { "Content-Type" => "application/json", "Stripe-Signature" => "t=1,v1=#{"a" * 64}" }
        expect(response).to have_http_status(:unauthorized)

        post funding_webhook_path("stripe"), params: "[1,2]",
          headers: { "Content-Type" => "application/json", "Stripe-Signature" => "t=1,v1=#{"b" * 64}" }
        expect(response).to have_http_status(:unauthorized)
      end

      expect(log.scan('"webhook" => {"body" => "unparsable"}').size).to eq(2)
      expect(log).not_to include("{not json")
      expect(log).not_to include("[1,2]")
    end
  end
end
