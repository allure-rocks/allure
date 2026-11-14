# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Segments::ElevationProfile do
  def point(distance, elevation)
    Allure::Segments::Point.new(
      index: 0,
      segment_index: 0,
      segment_point_index: 0,
      time: Time.utc(2026, 6, 1, 8, 0, 0),
      elapsed_time: 0,
      distance:,
      longitude: 6.0,
      latitude: 45.0,
      elevation:,
      speed: nil,
      heart_rate: nil,
      cadence: nil,
      power: nil
    )
  end

  describe ".dump" do
    it "stores distance/elevation pairs rebased from the first selected point" do
      profile = described_class.dump(
        [ point(100.0, 100.0), point(150.5, 105.0), point(200.0, 110.0) ]
      )

      expect(profile).to eq(
        [
          { "d" => 0.0, "ele" => 100.0 },
          { "d" => 50.5, "ele" => 105.0 },
          { "d" => 100.0, "ele" => 110.0 }
        ]
      )
    end

    it "returns an empty profile when no point carries an elevation" do
      expect(described_class.dump([ point(0.0, nil), point(100.0, nil) ])).to eq([])
      expect(described_class.dump([])).to eq([])
    end

    it "bounds a long profile while preserving the endpoints, extrema and null runs" do
      points = 500.times.map { |index| point(index.to_f, 100.0 + (index % 10)) }
      points[200] = point(200.0, 500.0)
      points[300] = point(300.0, nil)

      profile = described_class.dump(points, max_points: 100)

      expect(profile.length).to eq(100)
      expect(profile.first).to eq({ "d" => 0.0, "ele" => 100.0 })
      expect(profile.last).to eq({ "d" => 499.0, "ele" => 109.0 })
      expect(profile).to include({ "d" => 200.0, "ele" => 500.0 })
      expect(profile).to include({ "d" => 300.0, "ele" => nil })
    end
  end

  describe ".points" do
    it "returns the stored points with symbol keys and filters malformed entries" do
      segment = build(
        :segment,
        elevation_profile: [
          { "d" => 0.0, "ele" => 100.0 },
          { "d" => 25.5, "ele" => nil },
          { "d" => "bogus", "ele" => 3.0 },
          "not a hash"
        ]
      )

      expect(described_class.points(segment)).to eq(
        [
          { distance: 0.0, elevation: 100.0 },
          { distance: 25.5, elevation: nil }
        ]
      )
    end

    it "returns nothing for an unbuilt or empty profile" do
      expect(described_class.points(build(:segment))).to eq([])
      expect(described_class.points(build(:segment, elevation_profile: []))).to eq([])
    end
  end

  describe ".table" do
    it "samples the stored profile without recomputing it" do
      segment = build(:segment, elevation_profile: [
        { "d" => 0.0, "ele" => 10.0 },
        { "d" => 1.0, "ele" => 11.0 },
        { "d" => 2.0, "ele" => 12.0 },
        { "d" => 3.0, "ele" => 13.0 },
        { "d" => 4.0, "ele" => 14.0 }
      ])

      expect(described_class.table(segment, max_rows: 3)).to eq(
        [
          { distance: 0.0, elevation: 10.0 },
          { distance: 2.0, elevation: 12.0 },
          { distance: 4.0, elevation: 14.0 }
        ]
      )
      expect(described_class.table(segment, max_rows: 10).length).to eq(5)
    end
  end

  describe ".reverse" do
    it "mirrors the distances around the segment distance and keeps them ascending" do
      profile = [
        { "d" => 0.0, "ele" => 100.0 },
        { "d" => 100.0, "ele" => 110.0 },
        { "d" => 200.0, "ele" => 90.0 }
      ]

      expect(described_class.reverse(profile, distance: 200.0)).to eq(
        [
          { "d" => 0.0, "ele" => 90.0 },
          { "d" => 100.0, "ele" => 110.0 },
          { "d" => 200.0, "ele" => 100.0 }
        ]
      )
    end

    it "passes empty and nil profiles through untouched" do
      expect(described_class.reverse([], distance: 200.0)).to eq([])
      expect(described_class.reverse(nil, distance: 200.0)).to be_nil
    end
  end
end
