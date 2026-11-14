# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Outbox::EventBuilder do
  let(:actor) { create(:local_actor) }
  let(:remote_uri) { "https://remote.example/users/demo" }
  let(:payload) { { "type" => "Follow", "actor" => actor.uri, "object" => remote_uri } }
  let(:audience) { { "to" => [ remote_uri ], "cc" => [] } }
  let(:attributes) do
    {
      actor:,
      subject_type: "Actor",
      subject_id: actor.id,
      activity_type: "Follow",
      object_uri: actor.uri,
      payload:,
      audience:,
      idempotency_key: "follow:#{remote_uri}"
    }
  end

  it "creates one stable event for repeated calls" do
    first = described_class.new(**attributes).call!
    second = described_class.new(**attributes).call!

    expect(second).to eq(first)
    expect(FederationOutboxEvent.count).to eq(1)
    expect(first.payload.fetch("id")).to eq(first.activity_uri)
    expect(first.activity_uri).to eq("#{actor.uri}/activities/#{first.event_uuid}")
  end

  it "rejects a different payload for an existing activity identity" do
    described_class.new(**attributes).call!

    expect {
      described_class.new(**attributes.merge(payload: payload.merge("object" => "https://other.example/users/demo"))).call!
    }.to raise_error(described_class::IdentityConflict)
  end
end
