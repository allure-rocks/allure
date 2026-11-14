# frozen_string_literal: true

require "rails_helper"

RSpec.describe Funding::ManualGrant, :funding do
  let(:user) { create(:user) }
  let(:operator) { create(:user) }

  it "rolls the contribution back if its audit cannot be committed" do
    allow(Admin::Audit).to receive(:record).and_raise(ActiveRecord::RecordInvalid)
    expect do
      described_class.call(user:, actor: operator, tier: "coffee")
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(user.funding_contributions.reload).to be_empty
  end

  it "notifies the account only through a registered after-commit callback" do
    callback = nil
    allow(ActiveRecord).to receive(:after_all_transactions_commit) { |&block| callback = block }
    contribution = described_class.call(user:, actor: operator, tier: "coffee")
    expect(user.notifications.where(kind: "funding_recorded")).not_to exist
    expect(callback).to be_present
    callback.call
    notification = user.notifications.find_by!(kind: "funding_recorded")
    expect(notification.subject).to eq(contribution)
    expect(notification.actor).to be_nil
  end

  it "refuses a grant when the master switch is off" do
    ENV["FUNDING_ENABLED"] = "false"
    expect do
      described_class.call(user:, actor: operator, tier: "energy")
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(user.funding_contributions).to be_empty
    expect(AdminEvent.where(action: "funding_granted")).not_to exist
  end
end
