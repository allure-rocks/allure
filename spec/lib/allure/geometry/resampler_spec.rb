# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Geometry::Resampler do
  it "resamples by count while preserving endpoints" do
    coordinates = [ [ 0.0, 0.0 ], [ 0.005, 0.0 ], [ 0.01, 0.0 ] ]

    result = described_class.resample(coordinates, count: 5)

    expect(result.length).to eq(5)
    expect(result.first).to eq(coordinates.first)
    expect(result.last).to eq(coordinates.last)
    expect(result).to eq(described_class.resample(result, count: 5))
  end

  it "resamples by spacing and always includes the final endpoint" do
    coordinates = [ [ 0.0, 0.0 ], [ 0.01, 0.0 ] ]

    result = described_class.resample(coordinates, spacing: 400)

    expect(result.first).to eq(coordinates.first)
    expect(result.last).to eq(coordinates.last)
    expect(result.length).to be > 2
  end

  it "handles a degenerate two-point polyline" do
    coordinates = [ [ 1.0, 2.0 ], [ 1.0, 2.0 ] ]

    expect(described_class.resample(coordinates, count: 4)).to eq(Array.new(4, coordinates.first))
    expect(described_class.resample(coordinates, spacing: 10)).to eq([ coordinates.first, coordinates.last ])
  end

  it "takes the short path across the antimeridian" do
    result = described_class.resample([ [ 179.9, 0.0 ], [ -179.9, 0.0 ] ], count: 3)

    expect(result).to eq([ [ 179.9, 0.0 ], [ 180.0, 0.0 ], [ -179.9, 0.0 ] ])
  end

  it "rejects invalid sampling options" do
    expect { described_class.resample([ [ 0, 0 ], [ 1, 0 ] ], count: 1, spacing: 10) }
      .to raise_error(ArgumentError, /exactly one sampling mode/)
    expect { described_class.resample([ [ 0, 0 ], [ 1, 0 ] ], count: 1) }
      .to raise_error(ArgumentError, /at least two/)
  end
end
