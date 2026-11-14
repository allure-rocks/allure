# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::PublicationWithdrawal do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user:) }
  let(:publication) { publish_workout!(user:, workout:, profile:) }
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

  it "withdraws attempted recipients including retrying and withdrawn, and cancels only pending" do
    publication
    delivered_uri = "https://remote.example/users/delivered"
    retrying_uri = "https://remote.example/users/retrying"
    withdrawn_uri = "https://remote.example/users/withdrawn"
    pending_uri = "https://remote.example/users/pending"

    delivered = add_delivery(status: "delivered", recipient_uris: [ delivered_uri ])
    retrying = add_delivery(status: "retrying", recipient_uris: [ retrying_uri ])
    reconciling = add_delivery(status: "reconciling", recipient_uris: [ [ withdrawn_uri, "withdrawn" ] ])
    pending = add_delivery(status: "pending", recipient_uris: [ pending_uri ], attempts: 0)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    result = described_class.new(user:, workout:).call!

    expect(result.publication).to be_deleted
    expect(result.delete_event.payload["to"]).to contain_exactly(delivered_uri, retrying_uri, withdrawn_uri)
    expect(pending.reload).to be_cancelled
    expect(delivered.reload).to be_delivered
    expect(retrying.reload).to be_retrying
    expect(reconciling.reload.status).to eq("reconciling")
    expect(create_event.reload).not_to be_cancelled
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued
  end

  it "reconciles a Create that never attempted as cancelled" do
    publication
    pending = add_delivery(status: "pending", recipient_uris: [ "https://remote.example/users/never" ], attempts: 0)

    described_class.new(user:, workout:).call!

    expect(pending.reload).to be_cancelled
    expect(create_event.reload).to be_cancelled
  end

  it "is idempotent and never creates a second Delete" do
    publication
    first = described_class.new(user:, workout:).call!
    second = described_class.new(user:, workout:).call!

    expect(first.delete_event).to be_present
    expect(second.delete_event.id).to eq(first.delete_event.id)
    expect(FederationOutboxEvent.where(activity_type: "Delete", object_uri: publication.object_uri).count).to eq(1)
    expect(second.created).to be(false)
  end

  it "rejects non-owners" do
    publication
    other = create(:user)

    expect { described_class.new(user: other, workout:).call! }.to raise_error(ActiveRecord::RecordNotFound)
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

  it "treats enqueue failure as recoverable committed state" do
    publication
    allow(Federation::ExpandOutboxEventJob).to receive(:perform_later).and_raise(StandardError, "queue down")

    result = described_class.new(user:, workout:).call!

    expect(result.publication).to be_deleted
    expect(result.delete_event).to be_present
  end

  it "includes cancelled-after-attempt recipients that may have received Create" do
    publication
    attempted_uri = "https://remote.example/users/attempted-cancelled"
    never_uri = "https://remote.example/users/never-attempted"
    attempted = add_delivery(status: "cancelled", recipient_uris: [ attempted_uri ], attempts: 2)
    never = add_delivery(status: "cancelled", recipient_uris: [ never_uri ], attempts: 0)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    result = described_class.new(user:, workout:).call!

    expect(result.delete_event.payload["to"]).to include(attempted_uri)
    expect(result.delete_event.payload["to"]).not_to include(never_uri)
  end
end
