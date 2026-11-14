# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemoteSegmentRecipient do
  it "requires a local recipient and accepts the factory" do
    expect(build(:remote_segment_recipient)).to be_valid
    expect(build(:remote_segment_recipient, recipient_actor: build(:actor))).not_to be_valid
  end

  it "is unique per course and actor" do
    recipient = create(:remote_segment_recipient)

    expect(build(:remote_segment_recipient, remote_segment: recipient.remote_segment, recipient_actor: recipient.recipient_actor))
      .not_to be_valid
  end

  it "withdraws once with a bounded reason" do
    recipient = create(:remote_segment_recipient)

    recipient.withdraw!(reason: "blocked", at: Time.current)

    expect(recipient).to be_withdrawn
    expect(recipient.withdrawal_reason).to eq("blocked")
    expect { recipient.withdraw!(reason: "nonsense") }.to raise_error(ArgumentError)
  end
end
