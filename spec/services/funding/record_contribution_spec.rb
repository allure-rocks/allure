# frozen_string_literal: true

require "rails_helper"

RSpec.describe Funding::RecordContribution, :funding do
  let(:user) { create(:user) }
  let(:reference) { Funding::Reference.generate(user:, tier: "beer") }
  let!(:subscription) { create(:funding_subscription, user:) }
  let(:event) do
    Allure::Funding::Event.new(kind: "payment", external_id: "in_123", tier: "beer",
      reference:, paid_at: 1.hour.ago.change(usec: 0), amount_cents: 500, currency: "EUR",
      subscription_id: subscription.external_id, period_start: Time.utc(2026, 10, 1), period_end: Time.utc(2027, 10, 1))
  end

  def record(value = event) = described_class.call(provider: "stripe", event: value)

  it "freezes the verified facts and ignores repeated deliveries, including after revocation" do
    contribution = record
    expect(contribution.user).to eq(user)
    expect(contribution).to have_attributes(starts_at: event.period_start, expires_at: event.period_end, funding_subscription: subscription)
    contribution.revoke!
    replay = event.with(paid_at: Time.current, tier: "energy")
    expect { record(replay) }.not_to change(FundingContribution, :count)
    expect(contribution.reload).to have_attributes(status: "revoked", tier: "beer", paid_at: event.paid_at)
  end

  it "keeps unbound subscriptions unmatched without discarding the payment or trusting a fresh reference" do
    unmatched = create(:funding_subscription, user: nil)
    payment = event.with(subscription_id: unmatched.external_id)
    contribution = record(payment.with(reference: "forged"))
    expect(contribution.user).to be_nil
    expect(contribution.tier).to eq("beer")
    # A replay must not steal an unmatched payment by supplying a new reference.
    expect(record(payment).user).to be_nil
  end

  it "flags refunds without revoking, and retains the flag on a late payment event" do
    contribution = record(event.with(kind: "refund"))
    expect(contribution).not_to be_revoked
    expect(contribution.metadata).to eq("refund_reported" => true)
    record
    expect(contribution.reload.metadata).to eq("refund_reported" => true)
  end

  it "notifies once, only after commit, and never for an unmatched payment" do
    callbacks = []
    allow(ActiveRecord).to receive(:after_all_transactions_commit) { |&block| callbacks << block }
    2.times { record }
    expect(callbacks.size).to eq(1)
    expect(user.notifications).to be_empty
    callbacks.each(&:call)
    expect(user.notifications.where(kind: "funding_recorded").count).to eq(1)
    unmatched = create(:funding_subscription, user: nil)
    record(event.with(external_id: "in_other", subscription_id: unmatched.external_id, reference: nil))
    expect(callbacks.size).to eq(1)
  end

  it "rejects unsupported events and refuses to write while disabled" do
    expect { record(event.with(kind: "unverified")) }.to raise_error(ArgumentError)
    ENV["FUNDING_ENABLED"] = "false"
    expect { record }.to raise_error(ActiveRecord::RecordNotFound)
    expect(FundingContribution.count).to eq(0)
  end

  it "recovers the winner when another worker inserts the same payment" do
    winner = record
    allow(FundingContribution).to receive(:find_by).and_return(nil, winner)
    allow(FundingContribution).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
    expect(record).to eq(winner)
  end

  it "does not swallow invalid verified payment facts" do
    expect { record(event.with(amount_cents: -1)) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(FundingContribution.count).to eq(0)
  end

  it "records renewals through the durable binding, ignoring the expired checkout reference" do
    first = record
    renewal = event.with(external_id: "in_renewal", reference: "expired",
      period_start: event.period_end, period_end: event.period_end + 1.year)
    next_period = record(renewal)
    expect(next_period.user).to eq(user)
    expect(next_period.funding_subscription).to eq(first.funding_subscription)
    expect(next_period.expires_at).to eq(renewal.period_end)
    expect(next_period).not_to be_current
    expect(subscription.funding_contributions.count).to eq(2)
  end

  it "refuses to guess a subscription binding or a missing period" do
    expect { record(event.with(subscription_id: "unknown")) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { record(event.with(period_start: nil)) }.to raise_error(ArgumentError)
    expect { record(event.with(period_end: event.period_start)) }.to raise_error(ArgumentError)
    expect(FundingContribution.count).to eq(0)
  end

  it "keeps a late historical invoice without inventing a new paid year" do
    historical = event.with(period_start: 3.years.ago, period_end: 2.years.ago)
    contribution = record(historical)
    expect(contribution).to be_expired
    expect(contribution.expires_at).to be_within(0.000001).of(historical.period_end)
  end

  it "recovers paid invoices even when the subscription has since been canceled" do
    subscription.update!(status: "canceled", canceled_at: Time.current)
    contribution = record(event.with(reference: nil))
    expect(contribution.user).to eq(user)
    expect(contribution.expires_at).to eq(event.period_end)
  end
end
