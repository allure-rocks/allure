# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Funding administration", :funding do
  let(:operator) { create(:user, :with_totp, username: "operator") }
  let(:member) { create(:user) }

  around do |example|
    previous = ENV["INSTANCE_OPERATOR_USERNAME"]
    ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
    example.run
  ensure
    previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
  end

  it "refuses ordinary members without granting anything" do
    sign_in_as(member)
    post admin_account_funding_path(member), params: { tier: "energy" }
    expect(response).to have_http_status(:not_found)
    expect(FundingContribution.count).to eq(0)
  end

  it "records a year and audits the grant, then revokes idempotently" do
    sign_in_as(operator)
    post admin_account_funding_path(member), params: { tier: "beer" }
    expect(response).to redirect_to(admin_account_path(member))
    contribution = member.funding_contributions.sole
    expect(contribution.tier).to eq("beer")
    expect(contribution.expires_at).to eq(contribution.paid_at + 1.year)
    expect(AdminEvent.where(action: "funding_granted", subject: contribution)).to exist

    get admin_funding_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(member.display_name)

    2.times { delete admin_funding_contribution_path(contribution) }
    expect(contribution.reload).to be_revoked
    expect(AdminEvent.where(action: "funding_revoked", subject: contribution).count).to eq(1)
  end

  it "rejects invalid grants without audit rows" do
    sign_in_as(operator)
    post admin_account_funding_path(member), params: { tier: "gold" }
    expect(response).to redirect_to(admin_account_path(member))
    expect(FundingContribution.count).to eq(0)
    expect(AdminEvent.where(action: "funding_granted")).not_to exist
  end

  it "shows future paid periods as upcoming, with both billed boundaries" do
    sign_in_as(operator)
    contribution = create(:funding_contribution, :subscription, starts_at: 1.day.from_now)
    get admin_funding_path
    expect(response).to have_http_status(:ok)
    row = Nokogiri::HTML(response.body).at_css("tbody tr").text
    expect(row).to include(I18n.t("funding.admin.states.upcoming"))
    expect(row).to include(I18n.l(contribution.starts_at, format: :long), I18n.l(contribution.expires_at, format: :long))
  end

  it "shows reversal badges with kind, outcome and amount in the contributions table (PAY-105)" do
    sign_in_as(operator)
    subscription = create(:funding_subscription, user: member, provider: "stripe", external_id: "sub_123",
                           customer_id: "cus_123", tier: "coffee")
    contribution = create(:funding_contribution, :subscription, funding_subscription: subscription,
                           user: member, external_id: "in_123", amount_cents: 1000, currency: "EUR")
    create(:funding_reversal, :lost, funding_contribution: contribution, provider: "stripe",
                                      external_id: "dp_1", amount_cents: 1000, currency: "EUR")

    get admin_funding_path
    expect(response).to have_http_status(:ok)
    row = Nokogiri::HTML(response.body).at_css("tbody tr").text
    expect(row).to include(I18n.t("funding.admin.reversal_kinds.dispute"))
    expect(row).to include(I18n.t("funding.admin.reversal_statuses.lost"))
    expect(row).to include("10.00")
  end

  it "attaches an unmatched subscription and its invoices to a chosen account" do
    sign_in_as(operator)
    subscription = create(:funding_subscription, user: nil, provider: "stripe", external_id: "sub_123",
                          customer_id: "cus_123", tier: "coffee")
    contribution = create(:funding_contribution, :subscription, funding_subscription: subscription, user: nil)

    post admin_funding_subscription_attachment_path(subscription), params: { account_id: member.id }
    expect(response).to redirect_to(admin_funding_path)
    expect(subscription.reload.user).to eq(member)
    expect(contribution.reload.user).to eq(member)
    expect(AdminEvent.where(action: "funding_attached", subject: subscription)).to exist
    expect(member.notifications.where(kind: "funding_recorded").count).to eq(1)
  end

  it "returns 404 and performs no mutation while disabled, including for the operator" do
    sign_in_as(operator)
    contribution = create(:funding_contribution, user: member)
    ENV["FUNDING_ENABLED"] = "false"
    get admin_funding_path
    expect(response).to have_http_status(:not_found)
    post admin_account_funding_path(member), params: { tier: "energy" }
    expect(response).to have_http_status(:not_found)
    delete admin_funding_contribution_path(contribution)
    expect(response).to have_http_status(:not_found)
    expect(contribution.reload).not_to be_revoked
    expect(FundingContribution.count).to eq(1)
  end

  it "does not expose funding administration or accept grants in the companion" do
    sign_in_as(operator)
    headers = { "User-Agent" => "Allure iOS Hotwire Native" }
    get admin_funding_path, headers: headers
    expect(response).to have_http_status(:not_found)
    post admin_account_funding_path(member), params: { tier: "energy" }, headers: headers
    expect(response).to have_http_status(:not_found)
    expect(FundingContribution.count).to eq(0)
  end
end
