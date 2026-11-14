# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ScheduledPublicationCancellation do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user:) }
  let(:publication) do
    Workouts::Publisher.new(user:, workout:, profile:, delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day")).call!
  end

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "cancels terminally with no federation trace" do
    publication

    result = described_class.new(user:, workout:).call!

    expect(result.cancelled).to be(true)
    expect(publication.reload).to be_deleted
    expect(publication.deleted_at).to be_present
    expect(workout.reload.scheduled_publications.first).to be_nil
    expect(FederationOutboxEvent.where(workout_publication_id: publication.id)).to be_empty
  end

  it "is idempotent when the publication is passed explicitly" do
    publication
    described_class.new(user:, publication:).call!

    result = described_class.new(user:, publication:).call!

    expect(result.cancelled).to be(false)
    expect(publication.reload).to be_deleted
  end

  it "never touches an active publication" do
    active = publish_workout!(user:, workout:, profile:)

    expect {
      described_class.new(user:, workout:).call!
    }.to raise_error(ActiveRecord::RecordNotFound)
    expect(active.reload).to be_active
  end

  it "rejects a non-owner" do
    publication

    expect {
      described_class.new(user: create(:user), workout:).call!
    }.to raise_error(ActiveRecord::RecordNotFound)
    expect(publication.reload).to be_scheduled
  end

  it "honors the operator flag only for an instance operator" do
    publication

    expect {
      described_class.new(user: create(:user), workout:, operator: true).call!
    }.to raise_error(ActiveRecord::RecordNotFound)

    operator = create(:user, username: "operator")
    previous = ENV["INSTANCE_OPERATOR_USERNAME"]
    ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"

    result = described_class.new(user: operator, workout:, operator: true).call!

    expect(result.cancelled).to be(true)
    expect(publication.reload).to be_deleted
  ensure
    previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
  end
end
