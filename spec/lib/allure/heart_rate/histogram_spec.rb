# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::HeartRate::Histogram do
  let(:segment_class) { Struct.new(:points) }

  def segment(points) = segment_class.new(points)

  def point(time, heart_rate = nil, **extra)
    { "t" => time, "d" => 0.0 }.tap { it["hr"] = heart_rate unless heart_rate.nil? }.merge(extra.transform_keys(&:to_s))
  end

  def seconds_at(result, bpm) = result.histogram.fetch(bpm - described_class::RANGE.begin)

  it "credits each reading the time to the next point, to its bpm" do
    result = described_class.compute([ segment([ point(0, 120), point(5, 130), point(15, 130), point(16, 140) ]) ])

    expect(seconds_at(result, 120)).to eq(5)
    expect(seconds_at(result, 130)).to eq(11)
    expect(seconds_at(result, 140)).to eq(0)
    expect(result.sampled_seconds).to eq(16)
    expect(result.recorded_seconds).to eq(16)
    expect(result.covered_seconds).to eq(16)
    expect(result.coverage).to eq(1.0)
    expect(result.histogram.size).to eq(191)
  end

  it "leaves a pause inside a segment out of the coverage" do
    # A timer stop written as one point, then 15 minutes later the ride
    # resumes: the strap was fine, the device was paused.
    points = (0..60).map { point(it, 140) } + [ point(960, 140) ] + (961..1020).map { point(it, 140) }
    result = described_class.compute([ segment(points) ])

    expect(result.recorded_seconds).to eq(1020)
    expect(result.covered_seconds).to eq(150)
    expect(result.sampled_seconds).to eq(150)
    expect(result.coverage).to eq(1.0)
    expect(result).to be_usable
  end

  it "lowers the coverage when the strap, not the device, stops" do
    points = (0..100).map { point(it, it < 40 ? 140 + (it % 5) : nil) }
    result = described_class.compute([ segment(points) ])

    expect(result.covered_seconds).to eq(100)
    expect(result.sampled_seconds).to eq(40)
    expect(result.coverage).to be_within(0.001).of(0.4)
    expect(result).not_to be_usable
    expect(result.unusable_reason).to eq(:partial)
  end

  it "marks a recording whose points are mostly further apart than the cap as sparse" do
    result = described_class.compute([ segment((0..5).map { point(it * 600, 130) }) ])

    expect(result.sparse).to be(true)
    expect(result.coverage).to eq(1.0)
    expect(result).not_to be_usable
    expect(result.unusable_reason).to eq(:sparse)
  end

  it "skips the values a strap held while losing its signal" do
    # 20 s at 150, then 11 samples frozen at 172 over 10 s and 9 s without
    # heart rate.
    points = (0...20).map { point(it, 150) } + (20..30).map { point(it, 172) } +
             (31...40).map { point(it) } + [ point(40, 150), point(41, 150) ]
    result = described_class.compute([ segment(points) ])

    expect(seconds_at(result, 172)).to eq(0)
    expect(result.frozen_seconds).to eq(11)
    expect(seconds_at(result, 150)).to eq(21)
    expect(result.covered_seconds).to eq(41)
  end

  it "keeps a steady reading that is not followed by a loss" do
    result = described_class.compute([ segment((0..30).map { point(it, 172) }) ])

    expect(seconds_at(result, 172)).to eq(30)
    expect(result.frozen_seconds).to eq(0)
  end

  it "skips missing, non-positive and out-of-range readings" do
    result = described_class.compute([ segment([ point(0), point(1, 0), point(2, 250), point(3, 25), point(4, 100), point(5, 100) ]) ])

    expect(result.sampled_seconds).to eq(1)
    expect(result.covered_seconds).to eq(5)
    expect(seconds_at(result, 100)).to eq(1)
  end

  it "keeps recording segments apart and ignores the gap between them" do
    result = described_class.compute([
      segment([ point(0, 110), point(10, 110) ]),
      segment([ point(0, 160), point(20, 160) ])
    ])

    expect(seconds_at(result, 110)).to eq(10)
    expect(seconds_at(result, 160)).to eq(20)
    expect(result.recorded_seconds).to eq(30)
    expect(result.covered_seconds).to eq(30)
  end

  it "reads positionless points and rounds fractional readings" do
    result = described_class.compute([ segment([ point(0, 141.6), point(2.5, 141.6), point(5) ]) ])

    expect(seconds_at(result, 142)).to eq(5)
  end

  it "is empty without a beat" do
    result = described_class.compute([ segment([ point(0), point(60) ]), segment([]) ])

    expect(result).to be_empty
    expect(result).not_to be_usable
    expect(result.unusable_reason).to be_nil
    expect(result.recorded_seconds).to eq(60)
  end

  it "reads stored track segments like the analyzer's" do
    segment = TrackSegment.new(points: [ point(0, 120), point(10, 125), point(20, 125) ])

    expect(described_class.compute([ segment ]).sampled_seconds).to eq(20)
  end
end
