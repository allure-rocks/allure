# frozen_string_literal: true

require "rails_helper"

# docs/dev/HEART-RATE.md: nothing the heart-rate analysis derives ever leaves
# the owner, whatever the profile shares.
RSpec.describe "Heart-rate privacy" do
  let(:owner) { create(:user, max_heart_rate: 190, resting_heart_rate: 48) }
  let(:workout) { create(:workout, user: owner, average_heart_rate: 151, max_heart_rate: 176) }
  let!(:track_segment) do
    create(:track_segment, workout:, points: [
      { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074, "ele" => 100.0, "hr" => 140 },
      { "t" => 30, "d" => 125.0, "lat" => 45.0719, "lon" => 6.4083, "ele" => 106.0, "hr" => 165 },
      { "t" => 60, "d" => 250.0, "lat" => 45.0728, "lon" => 6.4092, "ele" => 112.0, "hr" => 176 }
    ])
  end

  it "keeps zones, histogram, load and profile out of the snapshot even when heart rate is shared" do
    HeartRates::Rebuild.new(workout:).call
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner,
                                                                   settings: PublishingProfile::DEFAULT_SETTINGS.merge(
                                                                     "metrics" => PublishingProfile::METRIC_KEYS,
                                                                     "mask_start" => false, "mask_finish" => false
                                                                   ))

    publication = Workouts::Publisher.new(user: owner, workout:, profile:).call!
    stored = JSON.generate([ publication.representation, publication.profile_snapshot, publication.route_metadata ])

    expect(publication.representation.to_s).to include("151")
    %w[zone histogram load sampled_seconds coverage fingerprint resting_heart_rate threshold].each do |key|
      expect(stored).not_to include(key)
    end
    expect(stored).not_to include("190")
  end
end
