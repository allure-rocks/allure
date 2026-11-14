# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Elevation::Profile do
  def samples(*pairs)
    pairs.map { |distance, elevation| { distance:, elevation: } }
  end

  it "interpolates linearly inside a contiguous run" do
    profile = described_class.new(samples([ 0.0, 100.0 ], [ 100.0, 200.0 ]))

    expect(profile.elevation_at(0.0)).to eq(100.0)
    expect(profile.elevation_at(25.0)).to eq(125.0)
    expect(profile.elevation_at(50.0)).to eq(150.0)
    expect(profile.elevation_at(100.0)).to eq(200.0)
  end

  it "has no elevation outside the sampled range" do
    profile = described_class.new(samples([ 0.0, 100.0 ], [ 100.0, 200.0 ]))

    expect(profile.elevation_at(-1.0)).to be_nil
    expect(profile.elevation_at(100.1)).to be_nil
    expect(profile.elevation_at(nil)).to be_nil
  end

  it "never interpolates across a missing sample" do
    profile = described_class.new(samples([ 0.0, 100.0 ], [ 50.0, nil ], [ 100.0, 200.0 ]))

    expect(profile.elevation_at(0.0)).to eq(100.0)
    expect(profile.elevation_at(25.0)).to be_nil
    expect(profile.elevation_at(50.0)).to be_nil
    expect(profile.elevation_at(75.0)).to be_nil
    expect(profile.elevation_at(100.0)).to eq(200.0)
  end

  it "resumes interpolation after a hole" do
    profile = described_class.new(
      samples([ 0.0, 100.0 ], [ 50.0, nil ], [ 100.0, 200.0 ], [ 200.0, 300.0 ])
    )

    expect(profile.elevation_at(150.0)).to eq(250.0)
  end

  it "accepts provider sample values and string-keyed stored rows" do
    sample = Data.define(:distance, :elevation).new(distance: 0.0, elevation: 120.0)
    stored = { "distance" => 100.0, "elevation" => 220.0 }
    profile = described_class.new([ sample, stored ])

    expect(profile.elevation_at(50.0)).to eq(170.0)
  end

  it "ignores invalid elevations" do
    profile = described_class.new(samples([ 0.0, Float::NAN ], [ 50.0, 100.0 ], [ 100.0, Float::INFINITY ]))

    expect(profile.elevation_at(0.0)).to be_nil
    expect(profile.elevation_at(50.0)).to eq(100.0)
    expect(profile.elevation_at(75.0)).to be_nil
  end

  it "has no elevation without any valid sample" do
    expect(described_class.new([]).elevation_at(0.0)).to be_nil
    expect(described_class.new(samples([ 0.0, nil ])).elevation_at(0.0)).to be_nil
  end
end
