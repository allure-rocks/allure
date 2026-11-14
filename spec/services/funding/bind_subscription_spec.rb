# frozen_string_literal: true

require "rails_helper"

RSpec.describe Funding::BindSubscription, :funding, :stripe_funding do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:created_at) { StripeFundingHelpers::STRIPE_TEST_CREATED_AT }

  def binding_value(reference:, created_at: self.created_at)
    Allure::Funding::CheckoutBinding.new(subscription_id: "sub_123", customer_id: "cus_123",
                                         tier: "coffee", reference:, created_at:)
  end

  it "binds a valid reference, keeps an existing match, and leaves invalid ones unmatched" do
    reference = travel_to(created_at) { Funding::Reference.generate(user:, tier: "coffee") }
    subscription = described_class.call(provider: "stripe", binding: binding_value(reference:, created_at:))
    expect(subscription.user).to eq(user)

    forged = described_class.call(provider: "stripe",
                                  binding: binding_value(reference: Funding::Reference.generate(user: create(:user), tier: "coffee"),
                                                         created_at:))
    expect(forged.reload.user).to eq(user)

    invalid = described_class.call(provider: "stripe",
                                   binding: binding_value(reference: "forged", created_at: created_at + 3.hours))
    expect(invalid.reload.user).to eq(user)
  end

  it "creates an unmatched row without a reference and attaches a late verified checkout" do
    unmatched = described_class.call(provider: "stripe", binding: binding_value(reference: nil))
    expect(unmatched.user).to be_nil
    expect(unmatched.status).to eq("incomplete")

    reference = travel_to(created_at) { Funding::Reference.generate(user:, tier: "coffee") }
    expect(described_class.call(provider: "stripe", binding: binding_value(reference:, created_at:)))
      .to eq(unmatched.reload)
    expect(unmatched.reload.user).to eq(user)
  end

  context "when the initial notification arrives after deletion was scheduled (PAY-101)" do
    let(:reference) { travel_to(created_at) { Funding::Reference.generate(user:, tier: "coffee") } }

    before { Users::DeletionSchedule.new(user:).schedule!(by: "self") }

    it "binds the deleting account as billing owner without granting a badge" do
      subscription = described_class.call(provider: "stripe", binding: binding_value(reference:, created_at:))

      expect(subscription.reload.user).to eq(user)
      expect(user.reload).to be_deactivated
      expect(user.funding_badge_visible?).to be(false)
    end

    it "attaches a pre-existing unmatched row and claims its unmatched invoices" do
      unmatched = described_class.call(provider: "stripe", binding: binding_value(reference: nil))
      create(:funding_contribution, :subscription, funding_subscription: unmatched)

      expect(described_class.call(provider: "stripe", binding: binding_value(reference:, created_at:)))
        .to eq(unmatched.reload)
      expect(unmatched.reload.user).to eq(user)
      expect(unmatched.funding_contributions.reload.map(&:user)).to all(eq(user))
    end

    it "does not cancel at the provider while the window is still open" do
      allow(Funding::Providers::Stripe).to receive(:cancel)

      described_class.call(provider: "stripe", binding: binding_value(reference:, created_at:))

      expect(Funding::Providers::Stripe).not_to have_received(:cancel)
    end

    it "cancels at the provider immediately once the deletion has started" do
      user.update!(deletion_started_at: Time.current)
      state = Allure::Funding::SubscriptionState.new(subscription_id: "sub_123", customer_id: "cus_123",
                                                     tier: "coffee", status: "active",
                                                     cancel_at_period_end: true, canceled_at: nil)
      allow(Funding::Providers::Stripe).to receive(:cancel).and_return(state)

      subscription = described_class.call(provider: "stripe", binding: binding_value(reference:, created_at:))

      expect(subscription.reload.user).to eq(user)
      expect(Funding::Providers::Stripe).to have_received(:cancel).with(subscription:)
      expect(subscription.reload.cancel_at_period_end).to be(true)
    end

    it "never cancels a subscription matched to another account, even past the cut-off" do
      user.update!(deletion_started_at: Time.current)
      other = create(:user)
      matched = create(:funding_subscription, user: other, provider: "stripe", external_id: "sub_123",
                                              customer_id: "cus_123", tier: "coffee")
      allow(Funding::Providers::Stripe).to receive(:cancel)

      # The reference belongs to the deleting account, but the subscription
      # row is already matched: the existing match wins and stays untouched.
      described_class.call(provider: "stripe", binding: binding_value(reference:, created_at:))

      expect(matched.reload.user).to eq(other)
      expect(Funding::Providers::Stripe).not_to have_received(:cancel)
    end
  end
end
