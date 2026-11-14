# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notification do
  it { expect(build(:notification)).to be_valid }

  it "accepts every declared kind" do
    described_class::KINDS.each do |kind|
      expect(build(:notification, kind:)).to be_valid, "expected #{kind} to be valid"
    end
  end

  it "rejects a kind outside the fixed list" do
    expect(build(:notification, kind: "nonsense")).not_to be_valid
  end

  it "requires object payload" do
    expect(build(:notification, payload: [])).not_to be_valid
    expect(build(:notification, payload: {})).to be_valid
  end

  it "starts unread and is marked read once" do
    notification = create(:notification)

    expect(notification).not_to be_read
    notification.mark_read!(at: Time.current)

    expect(notification.reload).to be_read
    expect { notification.mark_read!(at: 1.hour.from_now) }.not_to change { notification.reload.read_at }
  end

  it "orders newest first and scopes unread" do
    older = create(:notification, created_at: 2.days.ago)
    newer = create(:notification, created_at: 1.minute.ago)
    newer.mark_read!

    expect(described_class.recent_first).to eq([ newer, older ])
    expect(described_class.unread).to eq([ older ])
  end

  it "keeps one row per recipient, kind, and subject" do
    existing = create(:notification)
    duplicate = build(:notification, user: existing.user, kind: existing.kind, subject: existing.subject)

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects a kind outside the database constraint" do
    notification = create(:notification)

    expect { notification.update_column(:kind, "nonsense") }
      .to raise_error(ActiveRecord::StatementInvalid)
  end

  it "is destroyed with its recipient" do
    notification = create(:notification)

    notification.user.destroy!

    expect(described_class.where(id: notification.id)).not_to exist
  end

  it "keeps its history when the actor is deleted" do
    actor = create(:actor)
    notification = create(:notification, actor:, subject: nil)

    actor.delete

    expect(notification.reload.actor).to be_nil
    expect(notification.kind).to eq("follow_request")
  end
end
