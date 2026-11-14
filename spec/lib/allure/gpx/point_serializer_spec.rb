# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::PointSerializer do
  describe ".serialize" do
    it "always includes time, distance, and coordinates" do
      hash = described_class.serialize(
        time_offset_seconds: 12,
        cumulative_distance_metres: 34.84,
        latitude: 45.071,
        longitude: 6.4074
      )

      expect(hash).to eq(
        "t" => 12,
        "d" => 34.8,
        "lat" => 45.071,
        "lon" => 6.4074
      )
    end

    it "includes optional fields only when present" do
      hash = described_class.serialize(
        time_offset_seconds: 12,
        cumulative_distance_metres: 34.8,
        latitude: 45.071,
        longitude: 6.4074,
        elevation: 1420.23,
        speed_metres_per_second: 2.3141,
        heart_rate: 142,
        cadence: 84,
        power: 210
      )

      expect(hash).to eq(
        "t" => 12,
        "d" => 34.8,
        "lat" => 45.071,
        "lon" => 6.4074,
        "ele" => 1420.2,
        "v" => 2.31,
        "hr" => 142,
        "cad" => 84,
        "pw" => 210
      )
    end

    it "omits optional fields left nil" do
      hash = described_class.serialize(
        time_offset_seconds: 0,
        cumulative_distance_metres: 0.0,
        latitude: 45.071,
        longitude: 6.4074,
        elevation: nil,
        heart_rate: nil
      )

      expect(hash.keys).to contain_exactly("t", "d", "lat", "lon")
    end
  end
end
