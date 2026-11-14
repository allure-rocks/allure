# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::PublicationWithdrawal do
  let(:user) { create(:user) }
  let(:segment) { create(:segment, user:, visibility: "public") }
  let(:publication) { Segments::Publisher.new(user:, segment:).call! }
  let(:create_event) { FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri) }

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }
  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  def add_delivery(status:, recipient_uris:, attempts: 1)
    delivery = create(
      :federation_delivery,
      outbox_event: create_event,
      status:,
      inbox_url: "https://remote.example/inbox-#{SecureRandom.hex(4)}"
    )
    delivery.update_columns(attempts:) if attempts != delivery.attempts
    recipient_uris.each do |uri, recipient_status = "authorized"|
      create(:federation_delivery_recipient, delivery:, actor_uri: uri, status: recipient_status)
    end
    delivery
  end

  it "withdraws attempted recipients, cancels pending deliveries, and emits one Delete" do
    publication
    delivered_uri = "https://remote.example/users/delivered"
    retrying_uri = "https://remote.example/users/retrying"
    pending_uri = "https://remote.example/users/pending"

    delivered = add_delivery(status: "delivered", recipient_uris: [ delivered_uri ])
    retrying = add_delivery(status: "retrying", recipient_uris: [ retrying_uri ])
    pending = add_delivery(status: "pending", recipient_uris: [ pending_uri ], attempts: 0)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    result = described_class.new(user:, segment:).call!

    expect(result.publication).to be_deleted
    expect(result.delete_event).to have_attributes(
      subject_type: "SegmentPublication",
      segment_publication_id: publication.id,
      activity_type: "Delete"
    )
    expect(result.delete_event.payload["to"]).to contain_exactly(delivered_uri, retrying_uri)
    expect(pending.reload).to be_cancelled
    expect(delivered.reload).to be_delivered
    expect(retrying.reload).to be_retrying
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued
  end

  it "cancels a Create that never attempted" do
    publication
    pending = add_delivery(status: "pending", recipient_uris: [ "https://remote.example/users/never" ], attempts: 0)

    described_class.new(user:, segment:).call!

    expect(pending.reload).to be_cancelled
    expect(create_event.reload).to be_cancelled
  end

  it "is idempotent and never creates a second Delete" do
    publication
    first = described_class.new(user:, segment:).call!
    second = described_class.new(user:, segment:).call!

    expect(second.delete_event.id).to eq(first.delete_event.id)
    expect(FederationOutboxEvent.where(activity_type: "Delete", object_uri: publication.object_uri).count).to eq(1)
    expect(second.created).to be(false)
  end

  it "rejects non-owners" do
    publication
    other = create(:user)

    expect { described_class.new(user: other, segment:).call! }.to raise_error(ActiveRecord::RecordNotFound)
    expect(publication.reload).to be_active
  end

  it "lets an instance operator withdraw another owner's publication" do
    publication
    operator = create(:user, username: "operator")
    previous = ENV["INSTANCE_OPERATOR_USERNAME"]
    ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"

    result = described_class.new(user: operator, publication:, operator: true).call!

    expect(result.publication).to be_deleted
  ensure
    previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
  end

  it "ignores the operator flag for a non-operator" do
    publication
    other = create(:user)

    expect { described_class.new(user: other, publication:, operator: true).call! }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(publication.reload).to be_active
  end

  it "survives an enqueue failure with committed state" do
    publication
    allow(Federation::ExpandOutboxEventJob).to receive(:perform_later).and_raise(StandardError, "queue down")

    result = described_class.new(user:, segment:).call!

    expect(result.publication).to be_deleted
    expect(result.delete_event).to be_present
  end
end
