# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ActivateScheduledPublicationJob do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user:) }
  let(:publication) do
    Workouts::Publisher.new(user:, workout:, profile:, delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day")).call!
  end

  it "activates a due publication" do
    publication.update!(scheduled_for: 1.minute.ago)

    described_class.perform_now(publication)

    expect(publication.reload).to be_active
    expect(FederationOutboxEvent.where(activity_type: "Create", object_uri: publication.object_uri)).to exist
  end

  it "defers a publication whose planned moment is still ahead" do
    described_class.perform_now(publication)

    expect(publication.reload).to be_scheduled
  end

  it "is idempotent on already active publications" do
    publication.update!(scheduled_for: 1.minute.ago)
    described_class.perform_now(publication)
    event_count = FederationOutboxEvent.count

    described_class.perform_now(publication)

    expect(FederationOutboxEvent.count).to eq(event_count)
  end
end
