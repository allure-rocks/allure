# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::HeartRate::ZoneRanges do
  let(:zones) { Allure::HeartRate::Zones.new(max: 190, rest: nil, basis: "max", bounds: [ 60, 70, 80, 90 ]) }
  let(:segment_class) { Struct.new(:points, :distance) }

  # One point every 10 m with the given heart rates.
  def segment(heart_rates, step: 10.0)
    points = heart_rates.each_with_index.map do |bpm, index|
      { "t" => index * 5, "d" => index * step }.tap { it["hr"] = bpm if bpm }
    end
    segment_class.new(points, (heart_rates.size - 1) * step)
  end

  it "places each zone's stretches on the cumulative distance" do
    ranges = described_class.compute([ segment([ 120, 120, 120, 175, 175, 175, 175 ]) ], zones)

    expect(ranges[2]).to eq([ [ 0.0, 30.0 ] ])
    expect(ranges[5]).to eq([ [ 30.0, 60.0 ] ])
    expect(ranges[1]).to eq([])
  end

  it "joins same-zone stretches separated by a short excursion and drops slivers" do
    rates = ([ 120 ] * 6) + [ 175 ] + ([ 120 ] * 6)
    ranges = described_class.compute([ segment(rates) ], zones)

    expect(ranges[2]).to eq([ [ 0.0, 120.0 ] ])
    expect(ranges[5]).to eq([])
  end

  it "keeps stretches apart beyond the merge gap and offsets later recording segments" do
    first = segment([ 120, 120, 120 ], step: 100.0)
    second = segment([ 175, 175, 120, 120 ], step: 100.0)

    ranges = described_class.compute([ first, second ], zones)

    expect(ranges[2]).to eq([ [ 0.0, 200.0 ], [ 400.0, 500.0 ] ])
    expect(ranges[5]).to eq([ [ 200.0, 400.0 ] ])
  end

  it "skips readings without heart rate or outside the plausible range" do
    ranges = described_class.compute([ segment([ nil, nil, 250, 250, 0 ]) ], zones)

    expect(ranges.values).to all(be_empty)
  end
end
