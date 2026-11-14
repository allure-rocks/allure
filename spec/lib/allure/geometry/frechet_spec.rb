# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Geometry::Frechet do
  it "scores identical curves at zero" do
    curve = [ [ 0.0, 0.0 ], [ 0.005, 0.001 ], [ 0.01, 0.0 ] ]

    expect(described_class.distance(curve, curve)).to eq(0.0)
  end

  it "scores a uniformly offset curve by the offset" do
    offset = 10.0 / Allure::Gpx::Geo::EARTH_RADIUS_METRES * 180 / Math::PI
    reference = [ [ 0.0, 0.0 ], [ 0.01, 0.0 ] ]
    candidate = reference.map { |longitude, latitude| [ longitude, latitude + offset ] }

    expect(described_class.distance(reference, candidate, band: nil)).to be_within(0.01).of(10.0)
  end

  it "rejects a reversed traversal through endpoint ordering" do
    reference = [ [ 0.0, 0.0 ], [ 0.005, 0.0 ], [ 0.01, 0.0 ] ]

    expect(described_class.distance(reference, reference.reverse)).to be > 500
  end

  it "rejects a partial curve through endpoint pairing" do
    reference = [ [ 0.0, 0.0 ], [ 0.005, 0.0 ], [ 0.01, 0.0 ] ]
    partial = [ [ 0.002, 0.0 ], [ 0.008, 0.0 ] ]

    expect(described_class.distance(reference, partial)).to be > 100
  end

  # The plain recurrence over the full matrix, kept here as the definition the
  # two-row band walk has to reproduce cell for cell.
  def reference_distance(first, second, band)
    first_count = first.length
    second_count = second.length
    cells = Array.new(first_count) { Array.new(second_count, Float::INFINITY) }
    first_count.times do |i|
      second_count.times do |j|
        first_progress = first_count == 1 ? 0.0 : i.fdiv(first_count - 1)
        second_progress = second_count == 1 ? 0.0 : j.fdiv(second_count - 1)
        next if band && (first_progress - second_progress).abs > band

        cell = Allure::Gpx::Geo.horizontal_distance(first[i][1], first[i][0], second[j][1], second[j][0])
        cells[i][j] = if i.zero? && j.zero? then cell
        elsif i.zero? then [ cells[i][j - 1], cell ].max
        elsif j.zero? then [ cells[i - 1][j], cell ].max
        else [ [ cells[i - 1][j], cells[i - 1][j - 1], cells[i][j - 1] ].min, cell ].max
        end
      end
    end
    cells.last.last
  end

  def wobbly_curve(count, seed:)
    random = Random.new(seed)
    count.times.map { |index| [ 0.0005 * index + random.rand * 0.0001, 0.0002 * Math.sin(index / 7.0) + random.rand * 0.0001 ] }
  end

  it "walks the band with two rows and reproduces the full-matrix recurrence" do
    cases = [ [ 57, 43, 0.10 ], [ 40, 61, 0.25 ], [ 30, 30, 0.05 ], [ 1, 9, 0.1 ], [ 12, 1, 0.1 ], [ 4, 3, 0.0 ], [ 25, 26, 0.01 ] ]
    cases.each do |first_count, second_count, band|
      first = wobbly_curve(first_count, seed: first_count)
      second = wobbly_curve(second_count, seed: second_count * 3)

      expect(described_class.distance(first, second, band:)).to eq(
        [ reference_distance(first, second, band), reference_distance(first, second, nil) ].find(&:finite?)
      )
      expect(described_class.distance(first, second, band: nil)).to eq(reference_distance(first, second, nil))
    end
  end

  it "falls back to the full dynamic program when the band has no path" do
    reference = [ [ 0.0, 0.0 ], [ 0.003, 0.0 ], [ 0.006, 0.0 ], [ 0.009, 0.0 ] ]
    candidate = [ [ 0.0, 0.0 ], [ 0.0045, 0.0 ], [ 0.009, 0.0 ] ]

    expect(described_class.distance(reference, candidate, band: 0)).to eq(
      described_class.distance(reference, candidate, band: nil)
    )
  end

  it "preserves every threshold verdict and every accepted distance with a ceiling, including band fallback" do
    [ [ 57, 43, 0.10 ], [ 30, 30, 0.05 ], [ 1, 9, 0.1 ], [ 4, 3, 0.0 ], [ 25, 26, 0.01 ] ].each do |first_count, second_count, band|
      first = wobbly_curve(first_count, seed: first_count)
      second = wobbly_curve(second_count, seed: second_count * 3)
      exact = described_class.distance(first, second, band:)
      [ 0, 25, exact, exact + 1 ].each do |ceiling|
        bounded = described_class.distance(first, second, band:, ceiling:)

        expect(bounded <= ceiling).to eq(exact <= ceiling)
        expect(bounded).to eq(exact) if exact <= ceiling
      end
    end
  end

  it "skips geodesic calculations for cells that cannot meet the ceiling" do
    curve = wobbly_curve(200, seed: 1)
    allow(described_class).to receive(:horizontal_distance).and_call_original

    expect(described_class.distance(curve, curve, ceiling: 25)).to eq(0)
    expect(described_class).to have_received(:horizontal_distance).at_most(800).times
  end
end
