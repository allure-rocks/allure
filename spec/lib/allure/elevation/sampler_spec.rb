# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Elevation::Sampler do
  def point_at(distance, latitude: 0.0)
    longitude = distance / Allure::Gpx::Geo::EARTH_RADIUS_METRES * 180.0 / Math::PI
    Allure::Gpx::Point.new(time: distance, latitude:, longitude:)
  end

  def segment(*distances, latitude: 0.0)
    Allure::Gpx::Segment.new(points: distances.map { |distance| point_at(distance, latitude:) })
  end

  it "selects the first point, every interval, and the final point" do
    samples = described_class.call([ segment(*(0..300).step(10)) ], interval_metres: 50)

    expect(samples.map(&:distance)).to match([
      be_within(0.01).of(0.0),
      be_within(0.01).of(50.0),
      be_within(0.01).of(100.0),
      be_within(0.01).of(150.0),
      be_within(0.01).of(200.0),
      be_within(0.01).of(250.0),
      be_within(0.01).of(300.0)
    ])
  end

  it "includes the final point even when it falls between two intervals" do
    samples = described_class.call([ segment(*(0..330).step(10)) ], interval_metres: 50)

    expect(samples.map(&:distance)).to match([
      be_within(0.01).of(0.0),
      be_within(0.01).of(50.0),
      be_within(0.01).of(100.0),
      be_within(0.01).of(150.0),
      be_within(0.01).of(200.0),
      be_within(0.01).of(250.0),
      be_within(0.01).of(300.0),
      be_within(0.01).of(330.0)
    ])
  end

  it "keeps sampling across segments without resetting the interval" do
    samples = described_class.call(
      [ segment(0, 10, 20), segment(30, 40, 50) ],
      interval_metres: 20
    )

    expect(samples.map(&:distance)).to match([
      be_within(0.01).of(0.0),
      be_within(0.01).of(20.0),
      be_within(0.01).of(40.0),
      be_within(0.01).of(50.0)
    ])
  end

  it "does not spend samples on a stationary stretch" do
    points = [
      point_at(0), point_at(10),
      point_at(20), point_at(20), point_at(20), point_at(20),
      point_at(30), point_at(40), point_at(50)
    ]
    samples = described_class.call([ Allure::Gpx::Segment.new(points:) ], interval_metres: 10)

    expect(samples.map(&:distance)).to match([
      be_within(0.01).of(0.0),
      be_within(0.01).of(10.0),
      be_within(0.01).of(20.0),
      be_within(0.01).of(30.0),
      be_within(0.01).of(40.0),
      be_within(0.01).of(50.0)
    ])
  end

  it "splits samples into provider-sized batches without reordering" do
    samples = Array.new(205) do |index|
      Allure::Elevation::Sampler::Sample.new(distance: index.to_f, latitude: 0.0, longitude: 0.0)
    end

    chunks = described_class.chunks(samples, max_locations: 100)

    expect(chunks.map(&:length)).to eq([ 100, 100, 5 ])
    expect(chunks.flatten.map(&:distance)).to eq(samples.map(&:distance))
  end

  it "rejects a non-positive interval" do
    expect { described_class.call([ segment(0, 10) ], interval_metres: 0) }
      .to raise_error(ArgumentError, /interval_metres/)
  end
end
