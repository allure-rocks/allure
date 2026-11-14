# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Inbox::Recovery do
  let(:now) { Time.utc(2026, 10, 20, 12) }
  let(:recipient) { create(:local_actor) }

  def inbox_item(**attributes)
    create(:federation_inbox_item, recipient_actor: recipient, **attributes)
  end

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "enqueues again a due item whose job was lost" do
    item = inbox_item(status: "pending", next_attempt_at: now - 1.minute)
    inbox_item(status: "pending", next_attempt_at: now + 1.hour)
    inbox_item(status: "processed", processed_at: now)

    result = described_class.new(now:).call

    expect(result.enqueued).to eq(1)
    expect(Federation::ProcessInboxItemJob).to have_been_enqueued.with(item).once
  end

  it "retries an item a dead worker left processing" do
    item = inbox_item(status: "processing", attempts: 1)
    item.update_columns(updated_at: now - 20.minutes)

    result = described_class.new(now:).call

    expect(result.recovered).to eq(1)
    expect(item.reload).to be_pending
    expect(item.next_attempt_at).to be > now
    expect(Federation::ProcessInboxItemJob).to have_been_enqueued.with(item)
  end

  it "leaves an item still being processed alone" do
    item = inbox_item(status: "processing", attempts: 1)
    item.update_columns(updated_at: now - 1.minute)

    described_class.new(now:).call

    expect(item.reload).to be_processing
  end

  it "fails a stale item at its attempt limit" do
    item = inbox_item(status: "processing", attempts: FederationInboxItem::MAX_ATTEMPTS)
    item.update_columns(updated_at: now - 1.hour)

    described_class.new(now:).call

    expect(item.reload).to be_failed
    expect(Federation::ProcessInboxItemJob).not_to have_been_enqueued
  end
end
