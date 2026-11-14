# frozen_string_literal: true

require "rails_helper"

RSpec.describe Funding::CancelSubscriptions, :funding, :stripe_funding do
  let(:user) { create(:user) }

  it "stops every live renewal, even while the public funding switch is off" do
    subscription = create(:funding_subscription, user:, provider: "stripe", external_id: "sub_123", tier: "coffee")
    state = Allure::Funding::SubscriptionState.new(subscription_id: "sub_123", customer_id: "cus_123",
                                                   tier: "coffee", status: "active", cancel_at_period_end: true,
                                                   canceled_at: nil)
    allow(Funding::Providers::Stripe).to receive(:cancel).with(subscription:).and_return(state)

    ENV["FUNDING_ENABLED"] = "false"
    expect { described_class.call(user:) }.not_to raise_error
    expect(subscription.reload).to have_attributes(status: "active", cancel_at_period_end: true)
  end

  it "requires a registered adapter rather than silently leaving a renewal live" do
    create(:funding_subscription, user:, provider: "unknown_provider", external_id: "sub_unknown", tier: "coffee")
    expect { described_class.call(user:) }.to raise_error(Allure::Funding::Providers::ProviderError)
  end

  it "cancels one subscription through cancel_one and syncs the confirmed state" do
    subscription = create(:funding_subscription, user:, provider: "stripe", external_id: "sub_123", tier: "coffee")
    state = Allure::Funding::SubscriptionState.new(subscription_id: "sub_123", customer_id: "cus_123",
                                                   tier: "coffee", status: "active", cancel_at_period_end: true,
                                                   canceled_at: nil)
    allow(Funding::Providers::Stripe).to receive(:cancel).with(subscription:).and_return(state)

    described_class.cancel_one(subscription)

    expect(subscription.reload.cancel_at_period_end).to be(true)
    expect(subscription.synced_at).to be_present
  end

  it "raises from cancel_one when no adapter can cancel" do
    subscription = create(:funding_subscription, user:, provider: "unknown_provider", external_id: "sub_x",
                                                 tier: "coffee")
    expect { described_class.cancel_one(subscription) }
      .to raise_error(Allure::Funding::Providers::ProviderError)
  end
end
