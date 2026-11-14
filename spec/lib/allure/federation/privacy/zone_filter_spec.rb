# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Federation::Privacy::ZoneFilter do
  let(:zone) do
    Allure::Federation::Privacy::Zone.new(center: [ 0.0, 0.0 ], radius_meters: 1_000)
  end

  it "removes points inside zones and preserves visible runs" do
    result = described_class.new(
      segments: [ [ [ -0.02, 0.0 ], [ -0.005, 0.0 ], [ 0.005, 0.0 ], [ 0.02, 0.0 ], [ 0.03, 0.0 ] ] ],
      zones: [ zone ]
    ).call

    expect(result.segments).to eq([ [ [ 0.02, 0.0 ], [ 0.03, 0.0 ] ] ])
    expect(result.visible_points_count).to eq(2)
    expect(result).to be_points_removed
    expect(result).to be_interior_points_removed
    expect(result).to be_usable
    expect(result.bounds).to eq([ 0.0, 0.02, 0.0, 0.03 ])
  end

  it "blocks a visible edge crossing a zone without adding a synthetic point" do
    result = described_class.new(
      segments: [ [ [ -0.02, 0.0 ], [ 0.02, 0.0 ] ] ],
      zones: [ zone ]
    ).call

    expect(result.segments).to be_empty
    expect(result).to be_points_removed
    expect(result).not_to be_usable
  end

  it "keeps an unmasked start until the route first leaves every zone" do
    result = described_class.new(
      segments: [ [ [ -0.005, 0.0 ], [ 0.005, 0.0 ], [ 0.02, 0.0 ], [ 0.03, 0.0 ] ] ],
      zones: [ zone ],
      preserve_start: true
    ).call

    expect(result.segments).to eq([ [ [ -0.005, 0.0 ], [ 0.005, 0.0 ], [ 0.02, 0.0 ], [ 0.03, 0.0 ] ] ])
    expect(result).to be_usable
    expect(result).not_to be_points_removed
    expect(result).not_to be_interior_points_removed
  end

  it "keeps an unmasked finish from the route's last entry into a zone" do
    result = described_class.new(
      segments: [ [ [ -0.03, 0.0 ], [ 0.02, 0.0 ], [ -0.005, 0.0 ], [ 0.005, 0.0 ] ] ],
      zones: [ zone ],
      preserve_finish: true
    ).call

    expect(result.segments).to eq([ [ [ 0.02, 0.0 ], [ -0.005, 0.0 ], [ 0.005, 0.0 ] ] ])
    expect(result).to be_usable
    expect(result).to be_points_removed
    expect(result).not_to be_interior_points_removed
  end

  it "still filters interior points beyond the preserved prefix" do
    result = described_class.new(
      segments: [ [ [ -0.005, 0.0 ], [ 0.02, 0.0 ], [ 0.005, 0.0 ], [ 0.03, 0.0 ], [ 0.04, 0.0 ] ] ],
      zones: [ zone ],
      preserve_start: true
    ).call

    expect(result.segments).to eq([
      [ [ -0.005, 0.0 ], [ 0.02, 0.0 ] ],
      [ [ 0.03, 0.0 ], [ 0.04, 0.0 ] ]
    ])
    expect(result).to be_points_removed
    expect(result).to be_interior_points_removed
  end

  it "fails closed when a fully covered segment never leaves a zone" do
    points = [ [ -0.005, 0.0 ], [ 0.001, 0.0 ], [ 0.002, 0.0 ], [ 0.005, 0.0 ] ]

    result = described_class.new(segments: [ points ], zones: [ zone ], preserve_start: true, preserve_finish: true).call

    expect(result.segments).to be_empty
    expect(result).not_to be_usable
    expect(result).to be_points_removed

    prefix = described_class.new(segments: [ points ], zones: [ zone ], preserve_start: true).call
    expect(prefix.segments).to be_empty
    expect(prefix).not_to be_usable
  end

  it "preserves endpoints only on the first and last source segments" do
    result = described_class.new(
      segments: [
        [ [ -0.005, 0.0 ], [ 0.005, 0.0 ], [ 0.02, 0.0 ] ],
        [ [ 0.005, 0.0 ], [ -0.005, 0.0 ] ],
        [ [ 0.03, 0.0 ], [ 0.005, 0.0 ], [ -0.005, 0.0 ] ]
      ],
      zones: [ zone ],
      preserve_start: true,
      preserve_finish: true
    ).call

    expect(result.segments).to eq([
      [ [ -0.005, 0.0 ], [ 0.005, 0.0 ], [ 0.02, 0.0 ] ],
      [ [ 0.03, 0.0 ], [ 0.005, 0.0 ], [ -0.005, 0.0 ] ]
    ])
  end

  it "keeps source segments independent and computes bounds from output only" do
    result = described_class.new(
      segments: [
        [ [ 1.0, 1.0 ], [ 1.1, 1.1 ] ],
        [ [ 2.0, 2.0 ], [ 2.1, 2.1 ] ]
      ],
      zones: []
    ).call

    expect(result.segments).to eq([
      [ [ 1.0, 1.0 ], [ 1.1, 1.1 ] ],
      [ [ 2.0, 2.0 ], [ 2.1, 2.1 ] ]
    ])
    expect(result.visible_point_count).to eq(4)
    expect(result).not_to be_points_removed
    expect(result).not_to be_interior_points_removed
    expect(result.bounds).to eq([ 1.0, 1.0, 2.1, 2.1 ])
    expect(result.segments).to be_frozen
    expect(result.segments.first).to be_frozen
  end

  it "uses the shortest longitude path at the antimeridian" do
    antimeridian_zone = Allure::Federation::Privacy::Zone.new(center: [ 180.0, 0.0 ], radius_meters: 500)
    result = described_class.new(
      segments: [ [ [ 179.99, 0.0 ], [ -179.99, 0.0 ] ] ],
      zones: [ antimeridian_zone ]
    ).call

    expect(result.segments).to be_empty
  end

  it "fails closed for malformed coordinates and zones" do
    expect do
      described_class.new(segments: [ [ [ "6.4", 45.0 ], [ 6.5, 45.1 ] ] ], zones: []).call
    end.to raise_error(described_class::InvalidInput)

    expect do
      described_class.new(segments: [ [ [ 6.4, 45.0 ], [ 6.5, 45.1 ] ] ], zones: [ { radius_meters: 0 } ]).call
    end.to raise_error(described_class::InvalidInput)
  end
end
