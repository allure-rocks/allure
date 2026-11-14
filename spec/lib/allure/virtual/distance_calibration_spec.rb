# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Virtual::DistanceCalibration do
  let(:start) { Time.utc(2026, 9, 18, 17, 30, 0) }
  # About 7.7 m of longitude at Bled's latitude.
  let(:step) { 0.0001 }

  def point(index, latitude:, longitude:)
    Allure::Gpx::Point.new(
      time: start + index, latitude:, longitude:, elevation: nil,
      heart_rate: 150, cadence: 30, power: 200 + index
    )
  end

  def straight(count)
    (0...count).map { |index| point(index, latitude: 46.368, longitude: 14.1 - (index * step)) }
  end

  def lap(distance:, elapsed:)
    Allure::Gpx::Lap.new(number: 1, started_at: start, elapsed_time: elapsed, moving_time: elapsed, distance:)
  end

  def length(points)
    described_class.cumulative_distances(points).last
  end

  def segment(points) = Allure::Gpx::Segment.new(points:)

  it "fits a doubled track to the recorded lap distance, keeping times and signals" do
    points = straight(61)
    drawn = length(points)

    result = described_class.call(segments: [ segment(points) ], laps: [ lap(distance: drawn / 2, elapsed: 60) ])
    calibrated = result.first.points

    expect(length(calibrated)).to be_within(1e-3).of(drawn / 2)
    expect(calibrated.map(&:time)).to eq(points.map(&:time))
    expect(calibrated.map(&:power)).to eq(points.map(&:power))
    expect(calibrated.first.longitude).to be_within(1e-9).of(points.first.longitude)
    expect(calibrated.last.longitude).to be_within(1e-7).of(points[30].longitude)
  end

  it "keeps an out-and-back course on its outbound leg when it was drawn twice too long" do
    out = straight(31)
    # The return lane runs about 22 m north of the outbound one.
    back = (0..30).map { |index| point(31 + index, latitude: 46.3682, longitude: out[30 - index].longitude) }
    points = out + back
    drawn = length(points)

    calibrated = described_class.call(segments: [ segment(points) ], laps: [ lap(distance: drawn / 2, elapsed: 61) ]).first.points

    expect(length(calibrated)).to be_within(1e-3).of(drawn / 2)
    expect(calibrated.map(&:latitude)).to all(be < 46.36815)
    expect(calibrated.map(&:longitude).each_cons(2)).to all(satisfy { |a, b| b <= a })
  end

  it "extends a track drawn too short along its last direction" do
    points = straight(11)
    drawn = length(points)

    calibrated = described_class.call(segments: [ segment(points) ], laps: [ lap(distance: drawn * 1.05, elapsed: 10) ]).first.points

    expect(length(calibrated)).to be_within(1e-3).of(drawn * 1.05)
    expect(calibrated.last.longitude).to be < points.last.longitude
    expect(calibrated.map(&:latitude)).to all(be_within(1e-9).of(46.368))
  end

  it "counts the distance of a finish-line snap the analyzer would drop" do
    points = straight(31)
    snap = point(31, latitude: 46.368, longitude: points.last.longitude - (step * 8))
    recorded = length(points) + 60.0

    calibrated = described_class.call(segments: [ segment(points + [ snap ]) ], laps: [ lap(distance: recorded, elapsed: 31) ]).first.points

    expect(calibrated.length).to eq(31)
    expect(length(calibrated)).to be_within(1e-3).of(recorded)
  end

  it "holds a stationary start in place" do
    points = [ point(0, latitude: 46.368, longitude: 14.1), point(1, latitude: 46.368, longitude: 14.1) ] +
      straight(20).drop(1).each_with_index.map { |p, index| p.with(time: start + index + 2) }
    drawn = length(points)

    calibrated = described_class.call(segments: [ segment(points) ], laps: [ lap(distance: drawn / 2, elapsed: 21) ]).first.points

    expect(calibrated.first(2).map(&:longitude)).to all(be_within(1e-9).of(14.1))
    expect(length(calibrated)).to be_within(1e-3).of(drawn / 2)
  end

  it "scales every recording segment by the same ratio" do
    first = straight(11)
    second = straight(11).map { |p| p.with(time: p.time + 60, latitude: 46.37) }
    drawn = length(first) + length(second)

    result = described_class.call(segments: [ segment(first), segment(second) ], laps: [ lap(distance: drawn / 2, elapsed: 70) ])

    expect(result.sum { |s| length(s.points) }).to be_within(1e-3).of(drawn / 2)
    expect(result.map { |s| length(s.points) }).to match([
      be_within(1e-3).of(length(first) / 2), be_within(1e-3).of(length(second) / 2)
    ])
  end

  describe "fail-closed" do
    let(:points) { straight(61) }
    let(:segments) { [ segment(points) ] }

    it "leaves the track unchanged without laps" do
      expect(described_class.call(segments:, laps: [])).to equal(segments)
    end

    it "leaves a positionless recording unchanged" do
      points = [
        Allure::Gpx::Point.new(time: start, distance: 0),
        Allure::Gpx::Point.new(time: start + 1, distance: 10)
      ]
      positionless = [ segment(points) ]

      expect(described_class.call(segments: positionless, laps: [ lap(distance: 10, elapsed: 1) ]))
        .to equal(positionless)
    end

    it "leaves the track unchanged without a recorded lap distance" do
      expect(described_class.call(segments:, laps: [ lap(distance: nil, elapsed: 60) ])).to equal(segments)
    end

    it "leaves the track unchanged when the laps do not cover the recording" do
      expect(described_class.call(segments:, laps: [ lap(distance: length(points) / 2, elapsed: 30) ])).to equal(segments)
    end

    it "leaves the track unchanged when the ratio is implausible" do
      expect(described_class.call(segments:, laps: [ lap(distance: length(points) / 10, elapsed: 60) ])).to equal(segments)
    end

    it "leaves the track unchanged when it already matches" do
      expect(described_class.call(segments:, laps: [ lap(distance: length(points), elapsed: 60) ])).to equal(segments)
    end
  end
end
