# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::SummaryEligibility do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }

  it "needs the instance to offer the assistant" do
    user.update!(ai_enabled: true)

    expect(described_class.reason(workout)).to eq(:disabled)
  end

  context "when the instance offers it", :assistant do
    it "needs the owner's consent" do
      expect(described_class.reason(workout)).to eq(:not_consented)

      user.update!(ai_enabled: true)
      expect(described_class.reason(workout)).to be_nil
      expect(described_class).to be_eligible(workout)
    end

    it "refuses a deactivated account" do
      user.update!(ai_enabled: true, suspended_at: Time.current)

      expect(described_class.reason(workout)).to eq(:deactivated)
    end

    it "refuses a manual entry and a credit row" do
      user.update!(ai_enabled: true)
      manual = create(:workout, :manual, user:)
      credit = create(:workout, :credit, user:)

      expect(described_class.reason(manual)).to eq(:not_recording)
      expect(described_class.reason(credit)).to eq(:not_recording)
    end

    it "keeps a positionless or virtual recording eligible" do
      user.update!(ai_enabled: true)
      virtual = create(:workout, user:, sport: catalog_sport("cycling_virtual"))
      positionless = create(:workout, :unpositioned, user:)

      expect(described_class).to be_eligible(virtual)
      expect(described_class).to be_eligible(positionless)
    end

    it "scopes to consenting owners' recordings" do
      user.update!(ai_enabled: true)
      workout
      create(:workout, user: create(:user))
      create(:workout, :manual, user:)

      expect(described_class.scope).to contain_exactly(workout)
    end
  end
end
