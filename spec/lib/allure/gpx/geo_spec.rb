# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::Geo do
  def point(latitude, longitude, elevation = nil)
    Allure::Gpx::Point.new(time: Time.zone.now, latitude:, longitude:, elevation:)
  end

  describe ".normalize_longitude_delta" do
    it "leaves ordinary deltas unchanged" do
      expect(described_class.normalize_longitude_delta(1.0)).to eq(1.0)
      expect(described_class.normalize_longitude_delta(-1.0)).to eq(-1.0)
    end

    it "wraps deltas that cross the antimeridian to the shortest path" do
      expect(described_class.normalize_longitude_delta(-359.998)).to be_within(1e-9).of(0.002)
      expect(described_class.normalize_longitude_delta(359.998)).to be_within(1e-9).of(-0.002)
    end
  end

  describe ".horizontal_distance" do
    it "matches the equirectangular approximation for small deltas" do
      distance = described_class.horizontal_distance(0.0, 179.9990, 0.0, -179.9990)
      expect(distance).to be_within(0.01).of(222.63898158761023)
    end

    it "uses haversine for large deltas" do
      # Roughly a quarter of the Earth's circumference along the equator.
      distance = described_class.horizontal_distance(0.0, 0.0, 0.0, 90.0)
      expect(distance).to be_within(1.0).of((Math::PI / 2) * Allure::Gpx::Geo::EARTH_RADIUS_METRES)
    end

    it "is zero for identical points" do
      expect(described_class.horizontal_distance(45.0, 6.0, 45.0, 6.0)).to eq(0.0)
    end
  end

  describe ".distance" do
    it "falls back to 2D distance when either point has no elevation" do
      a = point(45.0000, 6.4000, nil)
      b = point(45.0010, 6.4000, 500.0)
      expect(described_class.distance(a, b)).to eq(described_class.horizontal_distance(45.0000, 6.4000, 45.0010, 6.4000))
    end

    it "treats elevation 0.0 as present and includes it in 3D distance" do
      a = point(45.0000, 6.4000, 0.0)
      b = point(45.0000, 6.4000, 10.0)
      expect(described_class.distance(a, b)).to eq(10.0)
    end

    it "combines horizontal and vertical deltas for 3D distance" do
      a = point(45.0000, 6.4000, 100.0)
      b = point(45.0010, 6.4000, 112.0)
      horizontal = described_class.horizontal_distance(45.0000, 6.4000, 45.0010, 6.4000)
      expect(described_class.distance(a, b)).to be_within(0.0001).of(Math.sqrt((horizontal**2) + (12.0**2)))
    end
  end
end
