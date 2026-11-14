# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Elevation::TrackGeometry do
  def point(latitude, longitude)
    Allure::Gpx::Point.new(time: 0, latitude:, longitude:)
  end

  def segment(*points)
    Allure::Gpx::Segment.new(points:)
  end

  it "returns one cumulative series per segment" do
    first = Allure::Gpx::Geo.horizontal_distance(50.0, 5.0, 50.0, 5.001)
    second = Allure::Gpx::Geo.horizontal_distance(50.0, 5.001, 50.0, 5.002)
    segments = [ segment(point(50.0, 5.0), point(50.0, 5.001), point(50.0, 5.002)) ]

    expect(described_class.cumulative_distances(segments)).to eq([ [ 0.0, first, first + second ] ])
  end

  it "continues the axis across a recording gap in document order" do
    first = Allure::Gpx::Geo.horizontal_distance(50.0, 5.0, 50.0, 5.001)
    gap = Allure::Gpx::Geo.horizontal_distance(50.0, 5.001, 50.0, 5.010)
    second = Allure::Gpx::Geo.horizontal_distance(50.0, 5.010, 50.0, 5.011)
    segments = [
      segment(point(50.0, 5.0), point(50.0, 5.001)),
      segment(point(50.0, 5.010), point(50.0, 5.011))
    ]

    expect(described_class.cumulative_distances(segments)).to eq([
      [ 0.0, first ],
      [ first + gap, first + gap + second ]
    ])
  end

  it "skips an empty segment without breaking the chain" do
    first = Allure::Gpx::Geo.horizontal_distance(50.0, 5.0, 50.0, 5.001)
    gap = Allure::Gpx::Geo.horizontal_distance(50.0, 5.001, 50.0, 5.002)
    segments = [
      segment(point(50.0, 5.0), point(50.0, 5.001)),
      Allure::Gpx::Segment.new(points: []),
      segment(point(50.0, 5.002))
    ]

    expect(described_class.cumulative_distances(segments)).to eq([ [ 0.0, first ], [], [ first + gap ] ])
  end
end
