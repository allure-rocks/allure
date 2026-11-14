# frozen_string_literal: true

require "rails_helper"

RSpec.describe FundingContribution do
  it { expect(build(:funding_contribution)).to be_valid }

  it "gives a manual contribution an idempotency key and one rolling year" do
    paid_at = Time.utc(2024, 2, 29, 12, 0, 0)
    contribution = create(:funding_contribution, paid_at:)

    expect(contribution.external_id).to start_with("manual-")
    expect(contribution.expires_at).to eq(Time.utc(2025, 2, 28, 12, 0, 0))
    expect(contribution.current?(paid_at + 11.months)).to be true
    expect(contribution.expired?(paid_at + 1.year)).to be true
  end

  it "allows an unmatched provider contribution but not an unmatched manual grant" do
    expect(build(:funding_contribution, user: nil, provider: "stripe", external_id: "payment-1",
      starts_at: Time.current, expires_at: 1.year.from_now)).to be_valid
    expect(build(:funding_contribution, user: nil, provider: "manual")).not_to be_valid
  end

  it "validates the fixed tier, status and provider vocabularies" do
    expect(build(:funding_contribution, tier: "gold")).not_to be_valid
    expect(build(:funding_contribution, status: "cancelled")).not_to be_valid
    expect(build(:funding_contribution, provider: "Stripe Payments")).not_to be_valid
  end

  it "enforces provider event idempotency" do
    existing = create(:funding_contribution)
    duplicate = build(:funding_contribution, provider: existing.provider, external_id: existing.external_id)

    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects oversized or non-object metadata" do
    expect(build(:funding_contribution, metadata: [])).not_to be_valid
    expect(build(:funding_contribution, metadata: { note: "x" * 4_100 })).not_to be_valid
  end

  it "keeps invalid tiers out at the database boundary" do
    contribution = create(:funding_contribution)
    expect { contribution.update_column(:tier, "gold") }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "selects only live rows and revokes without deleting history" do
    live = create(:funding_contribution)
    expired = create(:funding_contribution, :expired)
    revoked = create(:funding_contribution, :revoked)

    expect(described_class.current).to contain_exactly(live)

    revoked.revoke!
    expect(revoked.reload).to be_revoked
    expect(described_class.current).to contain_exactly(live)
  end

  it "is destroyed with its account" do
    contribution = create(:funding_contribution)

    contribution.user.destroy!

    expect(described_class.where(id: contribution.id)).not_to exist
  end

  describe "badge state" do
    let(:user) { create(:user) }

    it "uses the highest active tier, ignoring expired and revoked rows", :funding do
      create(:funding_contribution, user:, tier: "coffee")
      create(:funding_contribution, :energy, user:)
      create(:funding_contribution, :beer, :expired, user:)
      create(:funding_contribution, :revoked, user:, tier: "beer")

      expect(user.funding_badge_tier).to eq("energy")
      expect(user).to be_funding_badge_visible
    end

    it "can be hidden by the account", :funding do
      create(:funding_contribution, user:)
      user.update!(funding_badge_hidden: true)

      expect(user).not_to be_funding_badge_visible
    end

    it "disappears while the feature is disabled without deleting the contribution" do
      contribution = create(:funding_contribution, user:)

      with_disabled_funding do
        expect(user).not_to be_funding_badge_visible
        expect(contribution.reload).to be_present
      end
    end

    it "disappears for a deactivated account", :funding do
      create(:funding_contribution, user:)
      user.update!(suspended_at: Time.current)

      expect(user).not_to be_funding_badge_visible
    end
  end

  describe "paid periods" do
    let(:start) { Time.utc(2024, 2, 29, 12) }
    let(:finish) { Time.utc(2025, 2, 28, 12) }

    it "requires explicit period boundaries for provider payments" do
      contribution = build(:funding_contribution, provider: "stripe", external_id: "in_missing")
      expect(contribution).not_to be_valid
      expect(contribution.errors).to include(:starts_at, :expires_at)
    end

    it "preserves the billed anniversary for early, late and historical payments" do
      [ start - 1.day, start + 1.month, finish + 1.day ].each do |paid_at|
        contribution = create(:funding_contribution, :subscription, starts_at: start, expires_at: finish, paid_at:)
        contribution.revoke!
        expect(contribution.reload).to have_attributes(starts_at: start, expires_at: finish)
      end
    end

    it "uses a half-open period, both in Ruby and in SQL" do
      contribution = create(:funding_contribution, :subscription, starts_at: start, expires_at: finish)
      [ [ start - 1.second, false ], [ start, true ], [ finish - 1.second, true ], [ finish, false ] ].each do |at, current|
        expect(contribution.current?(at)).to eq(current)
        expect(described_class.current(at).exists?(id: contribution.id)).to eq(current)
      end
    end

    it "rejects empty or reversed periods in the model and database" do
      contribution = create(:funding_contribution, :subscription)
      contribution.expires_at = contribution.starts_at
      expect(contribution).not_to be_valid
      expect { contribution.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects a subscription from another provider or account" do
      contribution = build(:funding_contribution, :subscription)
      contribution.user = build(:user)
      expect(contribution).not_to be_valid
      contribution.user = contribution.funding_subscription.user
      contribution.provider = "helloasso"
      expect(contribution).not_to be_valid
    end

    it "does not count a future higher tier, even across a preload and time boundary", :funding do
      user = create(:user)
      create(:funding_contribution, user:)
      future = create(:funding_contribution, :subscription, :energy,
        funding_subscription: create(:funding_subscription, user:), starts_at: 1.day.from_now, expires_at: 1.year.from_now)
      expect(future).to be_upcoming
      expect(future.effective_status).to eq("upcoming")
      user.active_funding_contributions.load
      expect(user.funding_badge_tier).to eq("coffee")

      # An already preloaded row must not remain a badge after its paid expiry.
      user.active_funding_contributions.each { |row| row.expires_at = 1.second.ago }
      expect(user.funding_badge_tier).to be_nil
    end
  end

  def with_disabled_funding
    previous = ENV["FUNDING_ENABLED"]
    ENV.delete("FUNDING_ENABLED")
    yield
  ensure
    previous.nil? ? ENV.delete("FUNDING_ENABLED") : ENV["FUNDING_ENABLED"] = previous
  end
end
