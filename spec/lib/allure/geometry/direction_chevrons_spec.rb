# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Geometry::DirectionChevrons do
  it "places chevrons at a fixed spacing, clear of both endpoints" do
    placements = described_class.placements([ [ 0.0, 0.0 ], [ 1000.0, 0.0 ] ])

    expect(placements.length).to eq(3)
    expect(placements.first.x).to be_within(0.001).of(160.0)
    expect(placements.last.x).to be_within(0.001).of(800.0)
    placements.each_cons(2) do |before, after|
      expect(after.x - before.x).to be_within(0.001).of(320.0)
    end
  end

  it "follows the local direction of travel in canvas coordinates" do
    down = described_class.placements([ [ 0.0, 0.0 ], [ 0.0, 1000.0 ] ]).first
    up = described_class.placements([ [ 0.0, 1000.0 ], [ 0.0, 0.0 ] ]).first
    west = described_class.placements([ [ 1000.0, 0.0 ], [ 0.0, 0.0 ] ]).first

    expect(down.angle).to be_within(0.001).of(90.0)
    expect(up.angle).to be_within(0.001).of(-90.0)
    expect(west.angle).to be_within(0.001).of(180.0)
    expect(west.y).to be_within(0.001).of(0.0)
  end

  it "interpolates positions and tangents along a bent polyline" do
    placements = described_class.placements(
      [ [ 0.0, 0.0 ], [ 100.0, 0.0 ], [ 100.0, 500.0 ] ],
      spacing: 100.0,
      clearance: 0.0
    )

    expect(placements.length).to eq(6)
    expect(placements.first.x).to be_within(0.001).of(50.0)
    expect(placements.first.angle).to be_within(0.001).of(0.0)
    expect(placements.last.x).to be_within(0.001).of(100.0)
    expect(placements.last.y).to be_within(0.001).of(450.0)
    expect(placements.last.angle).to be_within(0.001).of(90.0)
  end

  it "moves a chevron off a corner instead of placing it on the turn" do
    placements = described_class.placements(
      [ [ 0.0, 0.0 ], [ 400.0, 0.0 ], [ 400.0, 900.0 ] ],
      spacing: 240.0,
      clearance: 0.0
    )

    expect(placements.map { |placement| placement.x.round(3) }).to eq([ 120.0, 320.0, 400.0, 400.0, 400.0 ])
    expect(placements.map { |placement| placement.angle.round(3) }).to eq([ 0.0, 0.0, 90.0, 90.0, 90.0 ])
    # The second slot is centred on 360, which is 40 px from the corner: the
    # straightest candidate retreats to 320 rather than sitting on the turn.
    expect(placements[1].x).to be_within(0.001).of(320.0)
    expect(placements[1].y).to be_within(0.001).of(0.0)
  end

  it "keeps the regular spacing on a jittery straight run" do
    points = Array.new(200) { |index| [ index * 5.0, index.odd? ? 0.6 : -0.6 ] }

    placements = described_class.placements(points, spacing: 240.0, clearance: 24.0)

    # The jitter lengthens the path, so the slot centres land at these x
    # positions; without the straightness tolerance they would wander through
    # the slot instead.
    expect(placements.map { |placement| placement.x.round(2) }).to eq([ 116.69, 350.06, 583.43, 816.81 ])
    expect(placements.map { |placement| placement.angle }).to all(be_within(0.5).of(0.0))
  end

  it "still places one chevron on a trace shorter than the first slot" do
    placements = described_class.placements([ [ 0.0, 0.0 ], [ 100.0, 0.0 ] ], clearance: 10.0)

    expect(placements.length).to eq(1)
    expect(placements.first.x).to be_within(0.001).of(50.0)
    expect(placements.first.angle).to be_within(0.001).of(0.0)
  end

  it "draws nothing for a segment too short to clear its endpoints" do
    expect(described_class.placements([ [ 0.0, 0.0 ], [ 40.0, 0.0 ] ])).to be_empty
    expect(described_class.placements([ [ 0.0, 0.0 ], [ 0.0, 0.0 ] ])).to be_empty
    expect(described_class.placements([ [ 0.0, 0.0 ] ])).to be_empty
  end

  it "does not accumulate arrows on repeated laps with shifted slots" do
    loop = [ [ 0, 0 ], [ 400, 0 ], [ 400, 400 ], [ 0, 400 ], [ 0, 0 ] ]
    once = described_class.placements(loop)
    repeated = described_class.placements(loop + loop.drop(1) + loop.drop(1))

    expect(repeated.length).to eq(once.length)
    expect(repeated.map(&:distance)).to all(be < 1600)
    expect(repeated.last.angle).to eq(-90)
  end

  it "shares coverage across recording gaps without removing opposite directions" do
    covered = {}
    outward = [ [ 0, 0 ], [ 1000, 0 ] ]

    expect(described_class.placements(outward, covered:).length).to eq(3)
    expect(described_class.placements(outward, covered:)).to be_empty
    expect(described_class.placements(outward.reverse, covered:).length).to eq(3)
  end
end
