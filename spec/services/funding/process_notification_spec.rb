# frozen_string_literal: true

require "rails_helper"

RSpec.describe Funding::ProcessNotification, :funding do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user) }
  let(:created_at) { Time.utc(2026, 10, 20, 10, 0, 0) }
  let(:reference) { travel_to(created_at) { Funding::Reference.generate(user:, tier: "coffee") } }

  let(:state) do
    Allure::Funding::SubscriptionState.new(subscription_id: "sub_123", customer_id: "cus_123", tier: "coffee",
                                           status: "active", cancel_at_period_end: false, canceled_at: nil)
  end

  let(:binding_value) do
    Allure::Funding::CheckoutBinding.new(subscription_id: "sub_123", customer_id: "cus_123", tier: "coffee",
                                         reference:, created_at:)
  end

  let(:event) do
    Allure::Funding::Event.new(kind: "payment", external_id: "in_123", tier: "coffee", reference:,
                               paid_at: created_at + 1.minute, amount_cents: 100, currency: "EUR",
                               subscription_id: "sub_123", period_start: created_at,
                               period_end: created_at + 1.year)
  end

  it "binds, refreshes and records a complete notification" do
    described_class.call(provider: "stripe", notification: Allure::Funding::Notification.new(
      event:, binding: binding_value, state:, reversal: nil
    ))
    subscription = FundingSubscription.sole
    expect(subscription).to have_attributes(user:, provider: "stripe", external_id: "sub_123",
                                            customer_id: "cus_123", tier: "coffee", status: "active")
    expect(FundingContribution.sole).to have_attributes(user:, external_id: "in_123",
                                                        starts_at: created_at, expires_at: created_at + 1.year)
  end

  it "applies only a subscription state, leaving unmatched management rows" do
    described_class.call(provider: "stripe", notification: Allure::Funding::Notification.new(
      event: nil, binding: nil, state:, reversal: nil
    ))
    expect(FundingSubscription.sole).to have_attributes(user: nil, status: "active")
    expect(FundingContribution.count).to eq(0)
  end

  it "attaches an earlier unmatched payment when a verified reference arrives late" do
    unmatched = create(:funding_subscription, user: nil, provider: "stripe", external_id: "sub_123",
                              customer_id: "cus_123", tier: "coffee")
    late = Allure::Funding::Event.new(kind: "payment", external_id: "in_late", tier: "coffee", reference: nil,
                                      paid_at: created_at + 1.minute, amount_cents: 100, currency: "EUR",
                                      subscription_id: "sub_123", period_start: created_at,
                                      period_end: created_at + 1.year)
    described_class.call(provider: "stripe", notification: Allure::Funding::Notification.new(
      event: late, binding: binding_value, state:, reversal: nil
    ))
    expect(FundingContribution.sole.user).to eq(user)
    expect(unmatched.reload.user).to eq(user)
  end

  it "rejects an unknown notification" do
    expect { described_class.call(provider: "stripe", notification: "no") }.to raise_error(ArgumentError)
  end

  it "binds a deleting account for billing only and records its payment without a notification (PAY-101)" do
    Users::DeletionSchedule.new(user:).schedule!(by: "self")

    described_class.call(provider: "stripe", notification: Allure::Funding::Notification.new(
      event:, binding: binding_value, state:, reversal: nil
    ))

    subscription = FundingSubscription.sole
    expect(subscription).to have_attributes(user:, status: "active")
    expect(FundingContribution.sole).to have_attributes(user:, external_id: "in_123")
    expect(Notification.where(kind: "funding_recorded")).to be_empty
  end
end
