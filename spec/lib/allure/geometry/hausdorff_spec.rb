# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Geometry::Hausdorff do
  # ~1.1 km east and ~0.55 km north, closed.
  SQUARE = [
    [ 0.0, 0.0 ],
    [ 0.01, 0.0 ],
    [ 0.01, 0.005 ],
    [ 0.0, 0.005 ],
    [ 0.0, 0.0 ]
  ].freeze

  def latitude_offset(meters)
    meters / Allure::Gpx::Geo::EARTH_RADIUS_METRES * 180 / Math::PI
  end

  it "scores identical curves at zero" do
    expect(described_class.symmetric_distance(SQUARE, SQUARE)).to be_within(0.001).of(0.0)
  end

  it "scores the same circuit started elsewhere at zero" do
    rotated = [ SQUARE[2], SQUARE[3], SQUARE[0], SQUARE[1], SQUARE[2] ]

    expect(described_class.symmetric_distance(SQUARE, rotated)).to be < 1.0
  end

  it "scores a uniformly offset curve by the offset" do
    offset = latitude_offset(10.0)
    candidate = SQUARE.map { |longitude, latitude| [ longitude, latitude + offset ] }

    expect(described_class.symmetric_distance(SQUARE, candidate)).to be_within(0.5).of(10.0)
  end

  it "scores a detour by its largest deviation" do
    detour = SQUARE.dup.insert(2, [ 0.015, 0.0025 ])

    expect(described_class.symmetric_distance(SQUARE, detour)).to be > 200
  end
end
