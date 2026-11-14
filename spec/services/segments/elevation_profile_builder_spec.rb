# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::ElevationProfileBuilder do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }
  let(:workout) { create(:workout, user:, sport:, points_count: 3, distance: 200.0) }

  before do
    create(
      :track_segment,
      workout:,
      position: 0,
      distance: 200.0,
      points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074, "ele" => 100.0 },
        { "t" => 30, "d" => 100.0, "lat" => 45.0710, "lon" => 6.4084, "ele" => 105.0 },
        { "t" => 60, "d" => 200.0, "lat" => 45.0710, "lon" => 6.4094, "ele" => 110.0 }
      ]
    )
  end

  def segment_without_profile
    segment = Segments::Creator.new(user:, workout:, name: "À reconstruire", start_index: 0, end_index: 2).call
    segment.update_columns(elevation_profile: nil)
    segment.reload
  end

  it "rebuilds the profile from the source stream" do
    profile = described_class.new(segment: segment_without_profile).call

    expect(profile).to eq(
      [
        { "d" => 0.0, "ele" => 100.0 },
        { "d" => 100.0, "ele" => 105.0 },
        { "d" => 200.0, "ele" => 110.0 }
      ]
    )
  end

  it "refuses a slice that no longer starts where the segment does" do
    segment = segment_without_profile
    segment.update_columns(
      start_point: RGeo::Geographic.spherical_factory(srid: 4326).point(0.0, 0.0)
    )

    expect(described_class.new(segment:).call).to eq([])
  end

  it "returns an empty profile without a source workout" do
    segment = segment_without_profile
    segment.update_columns(source_workout_id: nil)
    segment.reload

    expect(described_class.new(segment:).call).to eq([])
  end
end
