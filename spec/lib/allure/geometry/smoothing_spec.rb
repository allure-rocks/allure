# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Geometry::Smoothing do
  # ~16 m east between samples at 45°N: one Fibonacci-ish zigzag in latitude.
  def zigzag(length: 9)
    Array.new(length) do |index|
      [ 6.4 + (index * 0.0002), 45.0 + (index.odd? ? 0.00008 : -0.00008) ]
    end
  end

  it "preserves the point count and both endpoints" do
    points = zigzag
    smoothed = described_class.smooth(points, level: :medium)

    expect(smoothed.length).to eq(points.length)
    expect(smoothed.first).to eq(points.first)
    expect(smoothed.last).to eq(points.last)
  end

  it "leaves collinear points on the line" do
    points = Array.new(6) { |index| [ 6.4 + (index * 0.001), 45.0 ] }
    smoothed = described_class.smooth(points, level: :medium)

    smoothed.each_with_index do |point, index|
      expect(point[0]).to be_within(1e-9).of(points[index][0])
      expect(point[1]).to be_within(1e-9).of(points[index][1])
    end
  end

  it "reduces a lateral zigzag while keeping the overall shape" do
    points = zigzag
    smoothed = described_class.smooth(points, level: :medium)

    # Endpoints are fixed by contract, so compare the interior samples.
    interior = ->(series) { series[1..-2].map { |point| (point[1] - 45.0).abs }.max }
    raw_excursion = interior.call(points)
    smoothed_excursion = interior.call(smoothed)
    expect(smoothed_excursion).to be < raw_excursion
    expect(smoothed_excursion).to be > 0
    # The zigzag advances east: smoothing must not fold the route back.
    expect(smoothed.map(&:first)).to eq(smoothed.map(&:first).sort)
  end

  it "leaves a coarse track whose samples are farther apart than the window" do
    points = Array.new(5) { |index| [ 6.4 + (index * 0.002), 45.0 + (index.odd? ? 0.001 : 0.0) ] }
    smoothed = described_class.smooth(points, level: :light)

    expect(smoothed).to eq(points)
  end

  it "keeps stationary clusters finite and bounded to the sample cap" do
    points = Array.new(400) { [ 6.4, 45.0 ] }
    points << [ 6.4001, 45.0001 ]
    smoothed = described_class.smooth(points, level: :strong)

    expect(smoothed.length).to eq(points.length)
    expect(smoothed.flatten).to all(be_finite)
    expect(smoothed[1][1]).to be_within(1e-9).of(45.0)
  end

  it "rejects an unknown level and invalid coordinates" do
    expect { described_class.smooth(zigzag, level: :extreme) }.to raise_error(ArgumentError, /level/)
    expect { described_class.smooth([ [ 6.4, Float::NAN ] ], level: :medium) }.to raise_error(ArgumentError, /coordinate/)
    expect(described_class.valid_level?("medium")).to be(true)
    expect(described_class.valid_level?("huge")).to be(false)
  end
end
