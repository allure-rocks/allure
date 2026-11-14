# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::HeartRate::Zones do
  let(:zones) { described_class.new(max: 190, rest: nil, basis: "max", bounds: [ 60, 70, 80, 90 ]) }

  it "places the thresholds in percent of the maximum" do
    expect(zones.thresholds).to eq([ 114, 133, 152, 171 ])
    expect(zones.ranges).to eq([ [ nil, 113 ], [ 114, 132 ], [ 133, 151 ], [ 152, 170 ], [ 171, nil ] ])
  end

  it "places the thresholds in percent of the reserve" do
    reserve = described_class.new(max: 190, rest: 50, basis: "reserve", bounds: [ 60, 70, 80, 90 ])

    expect(reserve.thresholds).to eq([ 134, 148, 162, 176 ])
  end

  it "puts every bpm in the highest zone whose threshold it reaches" do
    expect(zones.zone_for(30)).to eq(1)
    expect(zones.zone_for(113)).to eq(1)
    expect(zones.zone_for(114)).to eq(2)
    expect(zones.zone_for(171)).to eq(5)
    expect(zones.zone_for(220)).to eq(5)
  end

  it "slices a histogram into five zones" do
    histogram = Array.new(Allure::HeartRate::Histogram::BINS, 0)
    histogram[100 - 30] = 60
    histogram[114 - 30] = 30
    histogram[200 - 30] = 10

    expect(zones.slice(histogram)).to eq([ 60, 30, 0, 0, 10 ])
  end

  it "fingerprints the profile, ignoring a resting value the basis does not use" do
    same = described_class.new(max: 190, rest: 55, basis: "max", bounds: [ 60, 70, 80, 90 ])
    other = described_class.new(max: 191, rest: nil, basis: "max", bounds: [ 60, 70, 80, 90 ])

    expect(same.fingerprint).to eq(zones.fingerprint)
    expect(other.fingerprint).not_to eq(zones.fingerprint)
    expect(zones.fingerprint).to match(/\A\h{16}\z/)
  end

  it "refuses a bound list of the wrong size" do
    expect { described_class.new(max: 190, rest: nil, basis: "max", bounds: [ 60, 70 ]) }.to raise_error(ArgumentError)
  end

  it "detects bounds that round to the same bpm" do
    narrow = described_class.new(max: 120, rest: 110, basis: "reserve", bounds: [ 50, 61, 62, 90 ])

    expect(zones).to be_distinct
    expect(narrow).not_to be_distinct
  end

  describe "load" do
    def histogram(seconds_by_bpm)
      Array.new(Allure::HeartRate::Histogram::BINS, 0).tap do |bins|
        seconds_by_bpm.each { |bpm, seconds| bins[bpm - 30] = seconds }
      end
    end

    it "places the floor ten points under the Z2 edge, in the zones' basis" do
      reserve = described_class.new(max: 190, rest: 50, basis: "reserve", bounds: [ 60, 70, 80, 90 ])

      expect(zones.load_floor_percent).to eq(50)
      expect(zones.load_floor).to eq(95)
      expect(reserve.load_floor).to eq(120)
    end

    it "weighs minutes by zone, Edwards' way" do
      # 10 min at 100 (Z1), 10 min at 120 (Z2), 1 min at 160 (Z4).
      expect(Allure::HeartRate::Load.edwards(histogram(100 => 600, 120 => 600, 160 => 60), zones)).to eq(34.0)
    end

    it "gives no load under the floor, while the time stays in Z1" do
      bins = histogram(80 => 1200, 100 => 600)

      expect(zones.slice(bins)).to eq([ 1800, 0, 0, 0, 0 ])
      expect(zones.below_floor_seconds(bins)).to eq(1200)
      expect(Allure::HeartRate::Load.edwards(bins, zones)).to eq(10.0)
    end
  end

  it "changes the fingerprint with the derivation method" do
    expect(zones.fingerprint).not_to eq(
      Digest::SHA256.hexdigest(JSON.generate([ "max", 190, nil, [ 60, 70, 80, 90 ] ]))[0, 16]
    )
  end
end
