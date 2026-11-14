# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemoteNoteRecipient do
  subject(:recipient) { build(:remote_note_recipient) }

  it "is valid from the factory and rejects remote recipients" do
    expect(recipient).to be_valid

    recipient.recipient_actor = build(:actor)
    expect(recipient).not_to be_valid
  end

  it "uniquely entitles one local actor per note" do
    existing = create(:remote_note_recipient)
    duplicate = build(:remote_note_recipient, remote_note: existing.remote_note, recipient_actor: existing.recipient_actor)

    expect(duplicate).not_to be_valid
  end

  it "withdraws once with a bounded reason" do
    recipient.save!

    recipient.withdraw!(reason: "unfollow")

    expect(recipient).to be_withdrawn
    expect(recipient.withdrawal_reason).to eq("unfollow")
    expect(recipient.withdrawn_at).to be_present
    expect { recipient.withdraw!(reason: "unknown") }.to raise_error(ArgumentError)
  end

  it "keeps the withdrawn state and timestamp in agreement" do
    recipient.status = "withdrawn"
    expect(recipient).not_to be_valid
  end
end
