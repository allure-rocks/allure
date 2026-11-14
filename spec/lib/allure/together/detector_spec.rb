# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Together::Detector do
  let(:sample) { Struct.new(:time, :latitude, :longitude) }

  let(:start) { Time.utc(2026, 9, 12, 8) }
  let(:metres_per_degree) { 111_320.0 }

  # A straight ride north from (45.0, 6.0) at `speed` m/s, one point every
  # `step` seconds, starting `delay` seconds after `start`, `offset_east`
  # metres to the east.
  def track(duration:, delay: 0, speed: 6.0, step: 5, offset_east: 0.0, from: 0, gap: nil)
    (from..duration).step(step).filter_map do |second|
      next if gap&.cover?(second)

      sample.new(start + delay + second, 45.0 + ((second * speed) / metres_per_degree),
                 6.0 + (offset_east / (metres_per_degree * Math.cos(45.0 * Math::PI / 180))))
    end
  end

  def recording(points, sport: "cycling", virtual: false, commute: false)
    described_class::Recording.new(sport_slug: sport, virtual:, commute:,
                                   moving_time: (points.last.time - points.first.time).to_i, points:)
  end

  def detect(first, second) = described_class.call(first, second)

  it "matches two recordings of the same ride at the same time" do
    result = detect(recording(track(duration: 3600)), recording(track(duration: 3600, offset_east: 15, step: 1)))

    expect(result).to be_match
    expect(result.matched_ratio).to be >= 0.99
    expect(result.overlap_seconds).to eq(3600)
  end

  it "matches across device variants of one family, and is symmetric" do
    first = recording(track(duration: 3600), sport: "cycling")
    second = recording(track(duration: 3600, offset_east: 20), sport: "cycling_road")

    expect(detect(first, second)).to be_match
    expect(detect(second, first)).to be_match
  end

  it "refuses different families, virtual sports and commutes" do
    points = track(duration: 3600)

    expect(detect(recording(points, sport: "cycling"), recording(points, sport: "running"))).not_to be_match
    expect(detect(recording(points, sport: "cycling_virtual", virtual: true), recording(points))).not_to be_match
    expect(detect(recording(points, commute: true), recording(points))).not_to be_match
  end

  it "refuses the same road ridden at another time" do
    expect(detect(recording(track(duration: 3600)), recording(track(duration: 3600, delay: 2 * 3600)))).not_to be_match
  end

  it "refuses a rider a few minutes behind on the same road" do
    expect(detect(recording(track(duration: 3600)), recording(track(duration: 3600, delay: 300)))).not_to be_match
  end

  it "refuses a parallel road two hundred metres away" do
    expect(detect(recording(track(duration: 3600)), recording(track(duration: 3600, offset_east: 200)))).not_to be_match
  end

  it "refuses riders who split halfway" do
    together = track(duration: 1800)
    apart = track(duration: 3600, from: 1805).map do |point|
      sample.new(point.time, point.latitude, point.longitude + 0.05)
    end

    expect(detect(recording(track(duration: 3600)), recording(together + apart))).not_to be_match
  end

  it "refuses the same loop ridden in the opposite direction at the same time" do
    loop_points = lambda do |direction|
      (0..3600).step(5).map do |second|
        angle = direction * 2 * Math::PI * second / 1200.0
        sample.new(start + second, 45.0 + (0.01 * Math.sin(angle)), 6.0 + (0.014 * Math.cos(angle)))
      end
    end

    expect(detect(recording(loop_points.call(1)), recording(loop_points.call(-1)))).not_to be_match
  end

  it "matches a participant who joined for part of a long ride" do
    long = recording(track(duration: 4 * 3600))
    joined = recording(track(duration: 3600 + 1800, from: 1800))

    expect(detect(long, joined)).to be_match
  end

  it "refuses an overlap shorter than the minimum, scaled to a short recording" do
    first = recording(track(duration: 2 * 3600))
    hand_over = recording(track(duration: 2 * 3600 + 600, from: 2 * 3600 - 600) +
                          track(duration: 4 * 3600, from: 2 * 3600 + 605, offset_east: 5000))
    brief = recording(track(duration: 3600 + 300, from: 3600))

    expect(detect(first, hand_over).overlap_seconds).to eq(600)
    expect(detect(first, hand_over)).not_to be_match
    expect(detect(first, brief)).to be_match
  end

  it "tolerates a short recording gap on one device" do
    expect(detect(recording(track(duration: 3600)), recording(track(duration: 3600, gap: 1200..1500)))).to be_match
  end

  it "returns no match for an empty recording" do
    expect(detect(recording(track(duration: 3600)), described_class::Recording.new(
      sport_slug: "cycling", virtual: false, commute: false, moving_time: 0, points: []
    ))).not_to be_match
  end

  describe Allure::Together::SportFamilies do
    it "mirrors the per-account sport defaults without their virtual members" do
      expected = Sport::DEFAULT_TARGET_SLUGS.transform_values { |slugs| slugs.reject { it.end_with?("_virtual") } }

      expect(described_class::FAMILIES).to eq(expected)
    end

    it "gives any other sport a family of its own" do
      expect(described_class.compatible?("rowing", "rowing")).to be(true)
      expect(described_class.compatible?("tennis", "running")).to be(false)
    end
  end
end
