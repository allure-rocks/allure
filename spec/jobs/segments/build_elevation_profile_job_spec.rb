# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::BuildElevationProfileJob do
  let(:workout) { create(:workout, user: create(:user), sport: catalog_sport("running")) }

  before do
    create(
      :track_segment,
      workout:,
      position: 0,
      distance: 100.0,
      points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074, "ele" => 100.0 },
        { "t" => 30, "d" => 100.0, "lat" => 45.0710, "lon" => 6.4084, "ele" => 110.0 }
      ]
    )
  end

  it "stores the rebuilt profile" do
    segment = create(
      :segment,
      source_workout: workout,
      source_start_index: 0,
      source_end_index: 1,
      start_point: RGeo::Geographic.spherical_factory(srid: 4326).point(6.4074, 45.0710),
      end_point: RGeo::Geographic.spherical_factory(srid: 4326).point(6.4084, 45.0710),
      distance: 100.0
    )

    described_class.perform_now(segment)

    expect(segment.reload.elevation_profile).to eq(
      [
        { "d" => 0.0, "ele" => 100.0 },
        { "d" => 100.0, "ele" => 110.0 }
      ]
    )
  end

  it "never overwrites an existing profile" do
    segment = create(:segment, elevation_profile: [ { "d" => 0.0, "ele" => 42.0 } ])

    described_class.perform_now(segment)

    expect(segment.reload.elevation_profile).to eq([ { "d" => 0.0, "ele" => 42.0 } ])
  end

  it "stamps an empty profile when the provenance no longer matches" do
    segment = create(
      :segment,
      source_workout: workout,
      source_start_index: 0,
      source_end_index: 1,
      distance: 100.0
    )

    described_class.perform_now(segment)

    expect(segment.reload.elevation_profile).to eq([])
  end
end
