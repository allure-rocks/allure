# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Climbs::Segmenter do
  # A sawtooth profile: `count` climbs of 1 km at 10 % separated by a short
  # descent and a flat approach, sampled every 50 m.
  def sawtooth(count)
    points = []
    distance = 0.0
    elevation = 500.0
    count.times do
      12.times { points << { distance: (distance += 50.0), elevation: }  }
      20.times { points << { distance: (distance += 50.0), elevation: (elevation += 5.0) } }
      8.times { points << { distance: (distance += 50.0), elevation: (elevation -= 6.0) } }
    end
    points
  end

  it "finds every climb of a profile under the cap, in track order" do
    climbs = described_class.new(points: sawtooth(5)).call

    expect(climbs.length).to eq(5)
    expect(climbs.map(&:start_distance)).to eq(climbs.map(&:start_distance).sort)
    expect(climbs.map(&:gain)).to all(be_within(15.0).of(100.0))
  end

  it "keeps at most max_climbs climbs on a profile with more candidates" do
    climbs = described_class.new(points: sawtooth(20)).call

    expect(climbs.length).to eq(described_class::LAP.max_climbs)
    expect(climbs.map(&:start_distance)).to eq(climbs.map(&:start_distance).sort)
  end

  # A flat valley floor, a steady 14 km climb at 7.5 % with no intermediate
  # dip (the Alpe d'Huez), then a long descent broken by a 25 m bump: too
  # small to be a climb from the dip before it, but 3 % on average from the
  # valley floor, over the summit.
  def alpine_profile
    points = []
    distance = 0.0
    elevation = 720.0
    40.times { points << { distance: (distance += 50.0), elevation: } }
    280.times { points << { distance: (distance += 50.0), elevation: (elevation += 3.75) } }
    120.times { points << { distance: (distance += 50.0), elevation: (elevation -= 3.0) } }
    10.times { points << { distance: (distance += 50.0), elevation: (elevation += 2.5) } }
    120.times { points << { distance: (distance += 50.0), elevation: (elevation -= 3.0) } }
    points
  end

  it "finds a long climb without an intermediate local minimum" do
    climbs = described_class.new(points: alpine_profile).call

    expect(climbs.length).to eq(1)
    climb = climbs.first
    expect(climb.start_distance).to be_within(150.0).of(2_000.0)
    expect(climb.end_distance).to be_within(150.0).of(16_000.0)
    expect(climb.gain).to be_within(20.0).of(1_050.0)
    expect(climb.average_grade).to be_within(0.005).of(0.075)
  end

  it "never starts a climb before a summit higher than its peak" do
    climbs = described_class.new(points: alpine_profile).call

    expect(climbs.map(&:end_distance)).to all(be < 17_000.0)
  end

  # A false summit: a 25 m dip, deeper than the extension budget, then a
  # 28 m rise, too small to be a climb on its own. Both summits reach back
  # to the same valley; only the stronger climb is kept.
  it "keeps the stronger of two overlapping climbs" do
    points = []
    distance = 0.0
    elevation = 500.0
    20.times { points << { distance: (distance += 50.0), elevation: } }
    40.times { points << { distance: (distance += 50.0), elevation: (elevation += 4.0) } }
    10.times { points << { distance: (distance += 50.0), elevation: (elevation -= 2.5) } }
    7.times { points << { distance: (distance += 50.0), elevation: (elevation += 4.0) } }
    20.times { points << { distance: (distance += 50.0), elevation: (elevation -= 5.0) } }

    climbs = described_class.new(points:).call

    expect(climbs.length).to eq(1)
    expect(climbs.first.start_distance).to be_within(150.0).of(1_000.0)
    expect(climbs.first.end_distance).to be_within(150.0).of(3_850.0)
  end

  it "returns nothing for a flat profile" do
    points = (1..40).map { |index| { distance: index * 50.0, elevation: 500.0 } }

    expect(described_class.new(points:).call).to be_empty
  end
end
