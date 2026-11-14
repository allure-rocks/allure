# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Outbox::Recovery do
  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }
  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  describe "pending event recovery" do
    it "enqueues expansion for events created while federation was disabled" do
      owner = create(:user)
      workout = create(:workout, user: owner)
      create(:track_segment, workout:)
      profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
      allow(Allure::Federation::Config).to receive(:enabled?).and_return(false)
      publication = publish_workout!(user: owner, workout:, profile:)
      allow(Allure::Federation::Config).to receive(:enabled?).and_call_original
      # The route image job finalizes the preparing intent regardless of
      # federation state; only expansion waits for the sweep.
      allow_any_instance_of(Workouts::MaplibreRouteImageRenderer).to receive(:call)
        .and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "no browser")
      Workouts::RenderPublicationRouteImageJob.perform_now(publication)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      result = described_class.new.call

      expect(result.events_enqueued).to eq(1)
      expect(Federation::ExpandOutboxEventJob).to have_been_enqueued
      expect(publication.reload).to be_active
    end

    it "releases a stale preparing intent so delivery is never stranded" do
      event = create(:federation_outbox_event, status: "preparing")
      event.update_columns(updated_at: 20.minutes.ago)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      result = described_class.new.call

      expect(result.preparing_finalized).to eq(1)
      expect(event.reload).to be_pending
      expect(Federation::ExpandOutboxEventJob).to have_been_enqueued
    end

    it "completes expansion with zero deliveries instead of stranding it" do
      actor = create(:local_actor)
      event = Federation::Outbox::EventBuilder.new(
        actor:,
        subject_type: "Actor",
        subject_id: actor.id,
        activity_type: "Follow",
        object_uri: actor.uri,
        idempotency_key: "recovery:zero:#{actor.id}",
        payload: { "type" => "Follow", "actor" => actor.uri, "object" => "https://remote.example/users/gone" },
        audience: { "to" => [ "https://remote.example/users/gone" ], "cc" => [] }
      ).call!
      resolver = instance_double(Federation::ActorResolver)
      allow(resolver).to receive(:resolve).and_raise(Federation::ActorResolver::InvalidActor, "gone")
      client = instance_double(Federation::Transport::Client)
      allow(client).to receive(:validate_url)

      Federation::Outbox::Expander.new(event:, actor_resolver: resolver, client:).call!

      expect(event.reload).to be_complete
    end
  end

  describe "delivery recovery" do
    it "re-enqueues due retrying deliveries" do
      delivery = create(:federation_delivery, status: "retrying", next_attempt_at: 1.minute.ago)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      result = described_class.new.call

      expect(result.deliveries_enqueued).to be >= 1
      expect(Federation::DeliverJob).to have_been_enqueued
      expect(delivery.reload).to be_retrying
    end

    it "reclaims expired delivering leases without creating new rows" do
      delivery = create(:federation_delivery, status: "delivering", lease_until: 1.minute.ago, attempts: 1)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      expect { described_class.new.call }.not_to change(FederationDelivery, :count)
      expect(Federation::DeliverJob).to have_been_enqueued
      expect(delivery.reload.status).to eq("delivering")
    end

    it "recovers stale reconciling deliveries with bounded backoff" do
      delivery = create(:federation_delivery, status: "reconciling")
      delivery.update_columns(updated_at: 1.hour.ago)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      result = described_class.new.call

      expect(result.reconciling_recovered).to eq(1)
      expect(delivery.reload).to be_retrying
      expect(delivery.next_attempt_at).to be_present
      expect(Federation::DeliverJob).to have_been_enqueued
    end
  end

  describe "terminal repair" do
    it "repairs expanded events whose deliveries are all terminal" do
      event = create(:federation_outbox_event, status: "expanded")
      delivery = create(:federation_delivery, outbox_event: event, status: "delivered")

      result = described_class.new.call

      expect(result.events_repaired).to eq(1)
      expect(event.reload).to be_complete
      expect(delivery.reload).to be_delivered
    end

    it "repairs expanded events with zero deliveries as complete" do
      event = create(:federation_outbox_event, status: "expanded")

      described_class.new.call

      expect(event.reload).to be_complete
    end

    it "leaves expanded events with non-terminal deliveries alone" do
      event = create(:federation_outbox_event, status: "expanded")
      create(:federation_delivery, outbox_event: event, status: "retrying", next_attempt_at: 1.hour.from_now)

      described_class.new.call

      expect(event.reload).to be_expanded
    end
  end

  describe "idempotency" do
    it "never creates duplicate event or delivery rows across repeated runs" do
      owner = create(:user)
      workout = create(:workout, user: owner)
      create(:track_segment, workout:)
      profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
      publish_workout!(user: owner, workout:, profile:)

      expect { described_class.new.call }.not_to change(FederationOutboxEvent, :count)
      expect { described_class.new.call }.not_to change(FederationDelivery, :count)
    end
  end
end
