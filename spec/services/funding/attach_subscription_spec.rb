# frozen_string_literal: true

require "rails_helper"

RSpec.describe Funding::AttachSubscription, :funding do
  let(:user) { create(:user) }
  let(:other) { create(:user) }
  let(:subscription) { create(:funding_subscription, user: nil, provider: "stripe", external_id: "sub_123", tier: "coffee") }

  it "attaches the subscription and its still-unmatched paid invoices, notifying once" do
    contribution = create(:funding_contribution, :subscription, funding_subscription: subscription, user: nil)
    callbacks = []
    allow(ActiveRecord).to receive(:after_all_transactions_commit) { |&block| callbacks << block }

    expect(described_class.call(subscription:, user:)).to be(true)
    expect(subscription.reload.user).to eq(user)
    expect(contribution.reload.user).to eq(user)
    expect { callbacks.each(&:call) }.to change { user.notifications.where(kind: "funding_recorded").count }.by(1)
  end

  it "never moves a matched subscription and never reaches a deactivated account" do
    matched = create(:funding_subscription, user:, provider: "stripe", external_id: "sub_123")
    expect { described_class.call(subscription: matched, user: other) }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(matched.reload.user).to eq(user)

    other.update!(suspended_at: Time.current)
    expect { described_class.call(subscription: unmatched_subscription, user: other) }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  def unmatched_subscription
    create(:funding_subscription, user: nil, provider: "stripe", external_id: "sub_other")
  end
end
