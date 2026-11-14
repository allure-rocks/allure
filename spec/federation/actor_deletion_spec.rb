# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::ActorDeletion do
  let(:now) { Time.utc(2026, 9, 11, 12) }
  let(:user) { create(:user) }
  let(:actor) { create(:local_actor, user:) }
  let(:remote_follower) { create(:actor, uri: "https://remote.example/users/follower") }

  before do
    create(:following, :accepted, follower_actor: remote_follower, followed_actor: actor)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "creates one signed actor Delete and tombstones the actor" do
    event = described_class.new(actor:, now:).call!

    expect(event.activity_type).to eq("Delete")
    expect(event.subject_type).to eq("Actor")
    expect(event.object_uri).to eq(actor.uri)
    expect(event.payload.dig("object", "type")).to eq("Tombstone")
    expect(event.payload.dig("object", "deleted")).to eq(now.utc.iso8601)
    expect(event.payload.fetch("recipients")).to include(remote_follower.uri)
    expect(event.payload.fetch("to")).to eq([ "#{actor.uri}/followers" ])
    expect(event.audience.fetch("recipients")).to include(remote_follower.uri)
    expect(actor.reload).to be_tombstoned
    expect(actor.user_id).to be_nil
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued
  end

  it "withdraws every active publication before tombstoning" do
    publication = create(:workout_publication, workout: create(:workout, user:))

    described_class.new(actor:, now:).call!

    expect(publication.reload).to be_deleted
    expect(
      FederationOutboxEvent.where(activity_type: "Delete", object_uri: publication.object_uri)
    ).to exist
  end

  it "withdraws active segment publications too" do
    segment = create(:segment, user:, visibility: "public")
    publication = Segments::Publisher.new(user:, segment:).call!

    described_class.new(actor:, now:).call!

    expect(publication.reload).to be_deleted
    expect(
      FederationOutboxEvent.where(activity_type: "Delete", object_uri: publication.object_uri)
    ).to exist
  end

  it "includes actors with attempted deliveries" do
    prior = create(:federation_outbox_event, actor:)
    delivery = create(:federation_delivery, outbox_event: prior)
    create(:federation_delivery_recipient, delivery:, actor_uri: "https://remote.example/users/liker")

    event = described_class.new(actor:, now:).call!

    expect(event.audience.fetch("recipients")).to include("https://remote.example/users/liker")
  end

  it "keeps the signed Delete event updatable after the actor is tombstoned" do
    event = described_class.new(actor:, now:).call!

    expect { event.mark_complete! }.not_to raise_error
    expect(event.reload).to be_complete
  end

  it "still requires a current actor when an event is created" do
    tombstoned = actor
    tombstoned.tombstone!(at: now)

    expect {
      FederationOutboxEvent.create!(
        actor: tombstoned,
        subject_type: "Actor",
        subject_id: tombstoned.id,
        activity_type: "Delete",
        object_uri: tombstoned.uri,
        event_uuid: SecureRandom.uuid,
        activity_uri: "#{tombstoned.uri}/activities/blocked",
        payload: { "type" => "Delete" },
        audience: { "to" => [], "cc" => [] }
      )
    }.to raise_error(ActiveRecord::RecordInvalid, /Actor/)
  end

  it "refuses to run for an already tombstoned actor" do
    actor.tombstone!(at: now)

    expect { described_class.new(actor:, now:).call! }
      .to raise_error(described_class::InvalidActor)
  end

  it "rejects a remote actor" do
    expect { described_class.new(actor: create(:actor), now:).call! }
      .to raise_error(described_class::InvalidActor)
  end
end
