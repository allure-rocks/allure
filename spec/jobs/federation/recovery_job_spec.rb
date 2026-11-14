# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::RecoveryJob do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user:) }

  it "activates due scheduled publications" do
    publication = Workouts::Publisher.new(
      user:, workout:, profile:, delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day")
    ).call!
    publication.update!(scheduled_for: 1.minute.ago)

    described_class.perform_now

    expect(publication.reload).to be_active
    expect(FederationOutboxEvent.where(activity_type: "Create", object_uri: publication.object_uri)).to exist
  end

  it "leaves future scheduled publications alone" do
    publication = Workouts::Publisher.new(
      user:, workout:, profile:, delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day")
    ).call!

    described_class.perform_now

    expect(publication.reload).to be_scheduled
    expect(FederationOutboxEvent.where(workout_publication_id: publication.id)).to be_empty
  end
end
