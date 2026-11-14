# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Audit do
  let(:operator) { create(:user) }

  it "records an event with actor, action, subject and metadata" do
    block = create(:federation_domain_block)

    event = described_class.record(
      actor: operator,
      action: :domain_blocked,
      subject: block,
      metadata: { "domain" => block.domain }
    )

    expect(event).to be_persisted
    expect(event.user).to eq(operator)
    expect(event.action).to eq("domain_blocked")
    expect(event.subject).to eq(block)
    expect(event.metadata).to eq("domain" => block.domain)
  end

  it "defaults metadata to an empty object" do
    event = described_class.record(actor: operator, action: :queue_paused)

    expect(event.metadata).to eq({})
    expect(event.subject).to be_nil
  end
end
