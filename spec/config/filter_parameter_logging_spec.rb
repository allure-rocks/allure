# frozen_string_literal: true

require "rails_helper"

# Authentication proofs never reach the log (docs/dev/AUTH.md): a parameter
# rename must not silently reopen the gap.
RSpec.describe "Log filtering" do
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  it "masks every authentication proof" do
    params = {
      "code" => "123456", "recovery_code" => "abcd-efgh", "assertion" => "{}", "credential" => "{}",
      "verifier" => "v", "token" => "t", "id_token" => "jwt", "password" => "p", "current_password" => "p",
      "user" => { "password" => "p", "password_confirmation" => "p" }
    }

    filtered = filter.filter(params)

    expect(filtered.except("user").values).to all(eq("[FILTERED]"))
    expect(filtered["user"].values).to all(eq("[FILTERED]"))
  end

  it "masks Sign in with Apple's user JSON without masking user forms" do
    filtered = filter.filter("user" => +'{"name":{"firstName":"Marie"},"email":"m@example.test"}')
    form = filter.filter("user" => { "username" => "marie", "display_name" => "Marie" })

    expect(filtered["user"]).to eq("[FILTERED]")
    expect(form["user"]).to eq("username" => "marie", "display_name" => "Marie")
  end

  it "keeps ordinary parameters readable" do
    expect(filter.filter("state" => "pending", "sort" => "last_seen_desc", "page" => "2"))
      .to eq("state" => "pending", "sort" => "last_seen_desc", "page" => "2")
  end

  it "masks the push subscription's endpoint and auth secret" do
    filtered = filter.filter(
      "endpoint" => "https://push.allure.rocks/v1/push/abc", "auth" => "secret",
      "p256dh" => "public-key"
    )

    expect(filtered["endpoint"]).to eq("[FILTERED]")
    expect(filtered["auth"]).to eq("[FILTERED]")
    expect(filtered["p256dh"]).to eq("public-key")
  end

  it "masks provider billing payloads, nested objects included (PAY-102)" do
    filtered = filter.filter(
      "id" => "evt_123", "type" => "invoice.paid",
      "data" => { "object" => {
        "id" => "in_123",
        "client_reference_id" => "signed_reference",
        "customer" => "cus_123",
        "charge" => "ch_123",
        "customer_details" => { "name" => "Marie Curie", "email" => "m@example.test",
                                "address" => { "line1" => "1 Rue de la Paix", "city" => "Paris" } },
        "billing_details" => { "name" => "Marie Curie", "address" => { "line1" => "1 Rue de la Paix" } },
        "hosted_invoice_url" => "https://invoice.stripe.com/i/acct_test/secret",
        "invoice_pdf" => "https://pay.stripe.com/invoice/acct_test/secret"
      } }
    )
    object = filtered["data"]["object"]

    # The operational envelope stays readable…
    expect(filtered["id"]).to eq("evt_123")
    expect(filtered["type"]).to eq("invoice.paid")
    expect(object["id"]).to eq("in_123")
    # …everything billing is masked, whole subtrees included.
    expect(object["client_reference_id"]).to eq("[FILTERED]")
    expect(object["customer"]).to eq("[FILTERED]")
    expect(object["charge"]).to eq("[FILTERED]")
    expect(object["customer_details"]).to eq("[FILTERED]")
    expect(object["billing_details"]).to eq("[FILTERED]")
    expect(object["hosted_invoice_url"]).to eq("[FILTERED]")
    expect(object["invoice_pdf"]).to eq("[FILTERED]")
  end

  it "masks the iOS handoff redirect" do
    redirect_filter = Array(Rails.application.config.filter_redirect)

    expect(redirect_filter.any? { |rule| rule.match?("allure://auth/handoff?token=abc") }).to be(true)
    expect(redirect_filter.any? { |rule| rule.match?("http://allure.test:3001/me") }).to be(false)
  end
end
