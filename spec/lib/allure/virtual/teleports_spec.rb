# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Virtual::Teleports do
  let(:start) { Time.utc(2026, 11, 6, 15, 42, 57) }

  def point(index, latitude: 46.368, longitude: 14.1, distance: nil, speed: nil)
    Allure::Gpx::Point.new(
      time: start + index, latitude:, longitude:, distance:, speed:
    )
  end

  it "marks the point after a jump the device's own distance does not follow" do
    points = [
      point(0, latitude: 46.368, longitude: 14.1, distance: 0),
      point(60, latitude: 46.374, longitude: 14.1, distance: 10)
    ]

    expect(described_class.marks(points)).to eq([ start + 60 ])
  end

  it "marks a jump with no recorded distance when the implied speed is absurd" do
    points = [
      point(0, latitude: 46.368, longitude: 14.1),
      point(1, latitude: 46.500, longitude: 14.1)
    ]

    expect(described_class.marks(points)).to eq([ start + 1 ])
  end

  it "keeps an ordinary step inside its segment" do
    points = [
      point(0, latitude: 46.368, longitude: 14.1, distance: 0),
      point(1, latitude: 46.368, longitude: 14.1001, distance: 7.7)
    ]

    expect(described_class.marks(points)).to be_empty
  end

  it "keeps a long gap the device's own distance explains" do
    points = [
      point(0, latitude: 46.368, longitude: 14.1, distance: 0),
      point(60, latitude: 46.368, longitude: 14.11, distance: 770)
    ]

    expect(described_class.marks(points)).to be_empty
  end

  it "ignores a jump shorter than the minimum step" do
    points = [
      point(0, latitude: 46.368, longitude: 14.1, distance: 0),
      point(1, latitude: 46.369, longitude: 14.1, distance: 10)
    ]

    expect(described_class.marks(points)).to be_empty
  end

  it "falls back to the device's speed when the file records no distance" do
    points = [
      point(0, latitude: 46.368, longitude: 14.1, speed: 1.0),
      point(60, latitude: 46.374, longitude: 14.1, speed: 1.0)
    ]

    expect(described_class.marks(points)).to eq([ start + 60 ])
  end

  it "never marks a positionless recording" do
    points = [
      point(0, latitude: nil, longitude: nil, distance: 0),
      point(1, latitude: nil, longitude: nil, distance: 10)
    ]

    expect(described_class.marks(points)).to be_empty
  end
end
