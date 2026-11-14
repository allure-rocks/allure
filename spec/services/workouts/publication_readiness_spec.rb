# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::PublicationReadiness do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }
  let!(:track_segment) { create(:track_segment, workout:) }

  it "reports a missing endpoint zone for a masked profile" do
    profile = create(:publishing_profile, user:)

    result = described_class.new(user:, workout:, profile:).call

    expect(result).not_to be_ready
    expect(result.warnings).to include(:endpoint_mask_start)
  end

  it "warns when an explicitly unmasked profile removes no interior points" do
    profile = create(:publishing_profile, :without_endpoint_masks, user:)

    result = described_class.new(user:, workout:, profile:).call

    expect(result).to be_ready
    expect(result.warnings).to include(:no_interior_points)
  end

  it "warns when an unmasked endpoint stays inside an active zone" do
    profile = create(:publishing_profile, :without_endpoint_masks, user:)
    create(:privacy_zone, user:)

    result = described_class.new(user:, workout:, profile:).call

    expect(result).to be_ready
    expect(result.warnings).to include(:endpoint_visible_start)
    expect(result.warnings).not_to include(:endpoint_visible_finish)
  end

  it "does not warn about an unmasked endpoint outside every zone" do
    track_segment.destroy!
    create(:track_segment, workout:, points: [
      { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074 },
      { "t" => 60, "d" => 100.0, "lat" => 45.0715, "lon" => 6.4080 },
      { "t" => 120, "d" => 200.0, "lat" => 45.0722, "lon" => 6.4086 },
      { "t" => 180, "d" => 300.0, "lat" => 45.0728, "lon" => 6.4092 }
    ])
    profile = create(:publishing_profile, user:)
    profile.update!(settings: profile.settings.merge("mask_start" => true, "mask_finish" => false))
    create(:privacy_zone, user:, latitude: 45.0710, longitude: 6.4074, radius_meters: 120)

    result = described_class.new(user:, workout:, profile:).call

    expect(result).to be_ready
    expect(result.warnings).not_to include(:endpoint_visible_start, :endpoint_visible_finish)
  end

  it "prepares the built-in followers profile whatever restricted federation says" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
    profile = create(:publishing_profile, :followers, :without_endpoint_masks, user:)

    result = described_class.new(user:, workout:, profile:).call

    expect(result).to be_ready
    expect(result.warnings).not_to include(:followers_unavailable)
  end
end
