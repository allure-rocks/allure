# frozen_string_literal: true

require "rails_helper"

RSpec.describe FundingSubscription do
  it "validates the provider identifiers and the closed lifecycle vocabulary" do
    expect(build(:funding_subscription)).to be_valid
    expect(build(:funding_subscription, user: nil)).to be_valid
    expect(build(:funding_subscription, provider: "manual")).not_to be_valid
    expect(build(:funding_subscription, customer_id: " ")).not_to be_valid
    expect(build(:funding_subscription, external_id: " ")).not_to be_valid
    expect(build(:funding_subscription, tier: "gold")).not_to be_valid
    expect(build(:funding_subscription, status: "trialing")).not_to be_valid
    expect(build(:funding_subscription, cancel_at_period_end: nil)).not_to be_valid
  end

  it "deduplicates the subscription, not its customer" do
    subscription = create(:funding_subscription)
    duplicate = build(:funding_subscription, external_id: subscription.external_id)
    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows multiple historical subscriptions for one provider customer" do
    subscription = create(:funding_subscription)
    expect(build(:funding_subscription, user: subscription.user, customer_id: subscription.customer_id)).to be_valid
  end

  it "allows an initial account match but refuses a later move or unlink" do
    subscription = create(:funding_subscription, user: nil)
    subscription.update!(user: create(:user))
    expect(subscription.update(user: create(:user))).to be false
    expect(subscription.update(user: nil)).to be false
  end

  it "does not grant a badge from active lifecycle state alone", :funding do
    subscription = create(:funding_subscription)
    expect(subscription.user).not_to be_funding_badge_visible
  end

  it "keeps paid periods valid across cancellation or a failed renewal", :funding do
    contribution = create(:funding_contribution, :subscription)
    subscription = contribution.funding_subscription
    %w[past_due paused canceled].each do |status|
      subscription.update!(status:, cancel_at_period_end: true, canceled_at: Time.current)
      expect(contribution.reload).to be_current
      expect(subscription.user).to be_funding_badge_visible
    end
    expect(subscription.funding_contributions.count).to eq(1)
  end

  it "protects invoice history from direct subscription deletion" do
    contribution = create(:funding_contribution, :subscription)
    expect { contribution.funding_subscription.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end

  it "is removed with its account after its contributions, including while funding is disabled", :funding do
    contribution = create(:funding_contribution, :subscription)
    id = contribution.funding_subscription_id
    ENV["FUNDING_ENABLED"] = "false"
    contribution.user.destroy!
    expect(described_class.where(id:)).not_to exist
    expect(FundingContribution.where(id: contribution.id)).not_to exist
  end

  it "enforces the status vocabulary in the database" do
    subscription = create(:funding_subscription)
    expect { subscription.update_column(:status, "invented") }.to raise_error(ActiveRecord::StatementInvalid)
  end
end
