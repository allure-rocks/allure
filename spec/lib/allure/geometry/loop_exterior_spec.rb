# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Geometry::LoopExterior do
  let(:clockwise_loop) { [ [ 0, 0 ], [ 400, 0 ], [ 400, 400 ], [ 0, 400 ], [ 0, 0 ] ] }
  let(:distances) { [ 120, 600, 1000, 1400 ] }

  it "chooses the outside of a single loop in either direction" do
    expect(described_class.sides(clockwise_loop, distances:)).to eq([ -1, -1, -1, -1 ])
    expect(described_class.sides(clockwise_loop.reverse, distances:)).to eq([ 1, 1, 1, 1 ])
  end

  it "leaves approach and exit arrows on the default side" do
    route = [ [ -400, 0 ] ] + clockwise_loop + [ [ 0, -400 ] ]
    expect(described_class.sides(route, distances: [ 100, 520, 1000, 1400, 1800, 2200 ]))
      .to eq([ 1, -1, -1, -1, -1, 1 ])
  end

  it "handles the opposite windings of a figure eight separately" do
    route = clockwise_loop + [ [ 0, -400 ], [ -400, -400 ], [ -400, 0 ], [ 0, 0 ] ]
    expect(described_class.sides(route, distances: [ 120, 600, 1000, 1400, 1720, 2200, 2600, 3000 ]))
      .to eq([ -1, -1, -1, -1, 1, 1, 1, 1 ])
  end

  it "finds a crossing between sparse edges without a recorded crossing vertex" do
    route = [ [ 0, 0 ], [ 400, 400 ], [ 0, 400 ], [ 400, 0 ], [ 0, 0 ] ]
    expect(described_class.sides(route, distances: [ 200, 500, 765, 1165, 1450, 1800 ]))
      .to eq([ 1, -1, -1, -1, 1, 1 ])
  end

  it "does not treat retracing or an open hairpin as an enclosed loop" do
    expect(described_class.sides([ [ 0, 0 ], [ 400, 0 ], [ 0, 0 ] ], distances: [ 120, 600 ]))
      .to eq([ 1, 1 ])
    expect(described_class.sides([ [ 0, 0 ], [ 400, 0 ], [ 400, 20 ], [ 0, 20 ] ], distances: [ 120, 600 ]))
      .to eq([ 1, 1 ])
  end

  it "tolerates approximate closure independent of projection origin and scale" do
    route = clockwise_loop[0...-1] + [ [ 0, 6 ] ]
    expect(described_class.sides(route, distances:)).to eq([ -1, -1, -1, -1 ])
    scaled = route.map { |x, y| [ 1e9 + x * 2, -1e9 + y * 2 ] }
    expect(described_class.sides(scaled, distances: distances.map { it * 2 }, closure: 20))
      .to eq([ -1, -1, -1, -1 ])
  end

  it "keeps repeated-lap arrows on the exterior" do
    repeated = clockwise_loop + clockwise_loop.drop(1) + clockwise_loop.drop(1)
    expect(Allure::Geometry::DirectionChevrons.placements(repeated).map(&:side)).to all(eq(-1))
  end

  it "returns the default side for short, stationary and empty geometries" do
    expect(described_class.sides([], distances: [ 120 ])).to eq([ 1 ])
    expect(described_class.sides([ [ 0, 0 ], [ 0, 0 ], [ 0, 0 ] ], distances: [ 0 ])).to eq([ 1 ])
    expect(described_class.sides(clockwise_loop, distances: [])).to eq([])
  end

  it "preserves an inner loop's winding when an outer loop closes later" do
    nested = [ [ 0, 0 ], [ 1000, 0 ], [ 1000, 200 ], [ 600, 200 ], [ 600, 600 ], [ 1000, 600 ], [ 1000, 200 ], [ 1000, 1000 ], [ 0, 1000 ], [ 0, 0 ] ]
    expect(described_class.sides(nested, distances: [ 120, 1320, 1800, 2200, 2600, 3000, 4200, 5400 ]))
      .to eq([ -1, 1, 1, 1, 1, -1, -1, -1 ])
  end
end
