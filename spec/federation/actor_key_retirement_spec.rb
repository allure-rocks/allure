# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::ActorKeyRetirement do
  let(:now) { Time.utc(2026, 9, 11, 12) }
  let(:user) { create(:user) }
  let(:actor) { create(:local_actor, user:) }

  it "retires the private key once every event and delivery is terminal" do
    event = create(:federation_outbox_event, actor:, status: "complete")
    create(:federation_delivery, outbox_event: event, status: "delivered", delivered_at: now)
    actor.tombstone!(at: now)

    result = described_class.new(now:).call

    expect(result.retired).to eq(1)
    expect(actor.reload.private_key_ciphertext).to be_nil
    expect(actor.private_key_retired_at).to be_present
  end

  it "waits while a non-terminal event remains" do
    create(:federation_outbox_event, actor:, status: "pending")
    actor.tombstone!(at: now)

    result = described_class.new(now:).call

    expect(result.retired).to eq(0)
    expect(result.waiting).to eq(1)
    expect(actor.reload.private_key_ciphertext).to be_present
    expect(actor.private_key_retired_at).to be_nil
  end

  it "waits while a non-terminal delivery remains" do
    event = create(:federation_outbox_event, actor:, status: "expanded")
    create(:federation_delivery, outbox_event: event, status: "pending")
    actor.tombstone!(at: now)

    expect(described_class.new(now:).call.retired).to eq(0)
  end

  it "ignores live actors" do
    create(:federation_outbox_event, actor:, status: "complete")

    expect(described_class.new(now:).call.retired).to eq(0)
    expect(actor.reload.private_key_ciphertext).to be_present
  end
end
