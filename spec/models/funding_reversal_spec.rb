# frozen_string_literal: true

require "rails_helper"

RSpec.describe FundingReversal do
  let(:contribution) { create(:funding_contribution, :subscription, provider: "stripe") }

  it "requires a kind-appropriate status and a unique provider identity" do
    refund = create(:funding_reversal, funding_contribution: contribution, provider: "stripe",
                                       kind: "refund", status: "succeeded")
    expect(refund).to be_persisted
    expect(build(:funding_reversal, funding_contribution: contribution, provider: "stripe",
                                    external_id: refund.external_id)).not_to be_valid
    expect(build(:funding_reversal, funding_contribution: contribution, provider: "stripe",
                                    kind: "refund", status: "lost")).not_to be_valid
    expect(build(:funding_reversal, funding_contribution: contribution, provider: "stripe",
                                    kind: "dispute", status: "lost")).to be_valid
  end

  it "cascades with its contribution" do
    reversal = create(:funding_reversal, funding_contribution: contribution, provider: "stripe")

    contribution.destroy!

    expect(FundingReversal.exists?(reversal.id)).to be(false)
  end
end
