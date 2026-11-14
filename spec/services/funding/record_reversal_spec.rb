# frozen_string_literal: true

require "rails_helper"

RSpec.describe Funding::RecordReversal, :funding do
  let(:user) { create(:user) }
  let!(:subscription) { create(:funding_subscription, user:, provider: "stripe", external_id: "sub_123") }
  let!(:contribution) do
    create(:funding_contribution, :subscription, funding_subscription: subscription, user:,
           provider: "stripe", external_id: "in_123", amount_cents: 1000, currency: "EUR")
  end
  let(:reversal) do
    Allure::Funding::Reversal.new(kind: "refund", external_id: "re_123", status: "succeeded",
                                  amount_cents: 400, currency: "EUR",
                                  reported_at: 1.hour.ago.change(usec: 0), payment_external_id: "in_123")
  end

  def record(value = reversal) = described_class.call(provider: "stripe", reversal: value)

  it "records a verified reversal against the original payment without ever rewriting it (PAY-105)" do
    row = record

    expect(row).to have_attributes(funding_contribution: contribution, kind: "refund", status: "succeeded",
                                   amount_cents: 400, currency: "EUR")
    expect(contribution.reload).to have_attributes(status: "active", amount_cents: 1000, metadata: {})
  end

  it "is idempotent on redelivery and updates only the reversal's own outcome" do
    record
    expect { record }.not_to change(FundingReversal, :count)

    dispute = reversal.with(kind: "dispute", external_id: "dp_1", status: "open")
    record(dispute)
    expect { record(dispute) }.not_to change(FundingReversal, :count)
    expect { record(dispute.with(status: "lost")) }.not_to change(FundingReversal, :count)

    expect(FundingReversal.find_by(external_id: "dp_1").status).to eq("lost")
    # The badge-after-refund policy is unchanged: never auto-revoked.
    expect(contribution.reload.status).to eq("active")
  end

  it "ignores reversals whose original payment was never recorded" do
    expect(record(reversal.with(payment_external_id: "in_unknown"))).to be_nil
    expect(FundingReversal.count).to eq(0)
  end

  it "rejects malformed reversals and refuses to write while disabled" do
    expect { record(reversal.with(kind: "chargeback")) }.to raise_error(ArgumentError)
    expect { record(reversal.with(status: "won")) }.to raise_error(ArgumentError) # not a refund status
    ENV["FUNDING_ENABLED"] = "false"
    expect { record }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
