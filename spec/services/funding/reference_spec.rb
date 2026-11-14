# frozen_string_literal: true

require "rails_helper"

RSpec.describe Funding::Reference do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:created_at) { Time.utc(2026, 10, 20, 10, 0, 0) }

  it "round-trips every tier within Stripe's URL parameter constraints" do
    Allure::Funding::TIERS.each do |tier|
      reference = described_class.generate(user:, tier:)
      expect(reference.length).to be <= 200
      expect(reference).to match(/\A[A-Za-z0-9_-]+\z/)
      expect(described_class.resolve(reference, tier:)).to eq(user)
    end
  end

  it "rejects tampering, missing references, and tier substitution" do
    reference = described_class.generate(user:, tier: "coffee")
    [ nil, "", reference + "a", "!" * 10, "x" * 201 ].each do |invalid|
      expect(described_class.resolve(invalid, tier: "coffee")).to be_nil
    end
    expect(described_class.resolve(reference, tier: "energy")).to be_nil
  end

  it "expires after two hours and never resolves a deactivated or deleted account" do
    reference = described_class.generate(user:, tier: "coffee")
    travel 2.hours do
      expect(described_class.resolve(reference, tier: "coffee")).to be_nil
    end
    user.update!(suspended_at: Time.current)
    expect(described_class.resolve(reference, tier: "coffee")).to be_nil
    user.destroy!
    expect(described_class.resolve(reference, tier: "coffee")).to be_nil
  end

  it "resolves a deletion-scheduled account for billing ownership only" do
    reference = described_class.generate(user:, tier: "coffee")
    user.update!(deletion_requested_at: Time.current, deletion_scheduled_at: 7.days.from_now,
                 deletion_requested_by: "self")

    # Benefit eligibility still rejects the deactivated account…
    expect(described_class.resolve(reference, tier: "coffee")).to be_nil
    # …but billing-lifecycle ownership resolves it, window and cut-off alike.
    expect(described_class.resolve(reference, tier: "coffee", for_billing: true)).to eq(user)
    user.update!(deletion_started_at: Time.current)
    expect(described_class.resolve(reference, tier: "coffee", for_billing: true)).to eq(user)

    # A purely suspended account is not billing-bound either.
    suspended = create(:user)
    suspended.update!(suspended_at: Time.current)
    suspended_reference = described_class.generate(user: suspended, tier: "coffee")
    expect(described_class.resolve(suspended_reference, tier: "coffee", for_billing: true)).to be_nil
  end

  it "checks delayed delivery at the provider-verified checkout creation time" do
    travel_to(created_at) { @reference = described_class.generate(user:, tier: "coffee") }

    # At the checkout's own creation time the reference was still valid, even
    # though the notification arrives after its two-hour lifetime.
    travel_to(created_at + 2.hours + 1.minute) do
      expect(described_class.resolve(@reference, tier: "coffee", at: created_at)).to eq(user)
      expect(described_class.resolve(@reference, tier: "coffee", at: created_at - 1.minute)).to be_nil
      expect(described_class.resolve(@reference, tier: "coffee", at: Time.current)).to be_nil
    end
  end
end
