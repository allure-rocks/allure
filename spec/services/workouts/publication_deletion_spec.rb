# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::PublicationDeletion do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:, title: "Withdrawn route") }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user:) }
  let(:publication) { publish_workout!(user:, workout:, profile:) }
  let(:create_event) { FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri) }
  let(:remote_uri) { "https://remote.example/users/follower" }

  it "creates a Delete event for recipients that received Create" do
    publication
    delivery = create(:federation_delivery, outbox_event: create_event)
    create(:federation_delivery_recipient, delivery:, actor_uri: remote_uri)
    delivery.mark_delivered!(response_status: 202)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    deleted = described_class.new(user:, workout:).call!.sole

    expect(deleted).to be_deleted
    expect(create_event.reload.deliveries.first).to be_delivered
    delete_event = FederationOutboxEvent.find_by!(activity_type: "Delete", object_uri: publication.object_uri)
    expect(delete_event.payload).to include(
      "type" => "Delete",
      "actor" => user.actor_uri,
      "object" => publication.object_uri,
      "to" => [ remote_uri ]
    )
    expect(delete_event.audience).to include("recipients" => [ remote_uri ])
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued
  end

  it "cancels a pending Create delivery and does not target it for Delete" do
    publication
    delivery = create(:federation_delivery, outbox_event: create_event)
    create(:federation_delivery_recipient, delivery:, actor_uri: remote_uri)

    described_class.new(user:, workout:).call!

    expect(delivery.reload).to be_cancelled
    delete_event = FederationOutboxEvent.find_by!(activity_type: "Delete", object_uri: publication.object_uri)
    expect(delete_event.audience.fetch("recipients")).to eq([])

    expect {
      Federation::Outbox::Expander.new(event: create_event).call!
    }.not_to change(FederationDelivery, :count)
    expect(create_event.reload).to be_cancelled
  end
end
