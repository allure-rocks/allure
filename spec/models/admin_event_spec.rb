# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminEvent do
  it "accepts every declared action" do
    described_class::ACTIONS.each do |action|
      expect(build(:admin_event, action:)).to be_valid, "expected #{action} to be valid"
    end
  end

  it "rejects an action outside the fixed list" do
    expect(build(:admin_event, action: "nonsense")).not_to be_valid
  end

  it "requires object metadata" do
    expect(build(:admin_event, metadata: [])).not_to be_valid
    expect(build(:admin_event, metadata: {})).to be_valid
  end

  it "is append-only" do
    event = create(:admin_event)

    expect { event.update!(action: "domain_unblocked") }
      .to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "keeps its history when the actor is deleted" do
    event = create(:admin_event)

    event.user.destroy!

    expect(event.reload.user).to be_nil
    expect(event.action).to eq("domain_blocked")
  end
end
