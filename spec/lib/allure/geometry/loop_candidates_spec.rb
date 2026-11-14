# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Geometry::LoopCandidates do
  def coordinate(x, y)
    [ x / 111_319.49, y / 111_319.49 ]
  end

  def square
    [ [ 0, 0 ], [ 200, 0 ], [ 200, 200 ], [ 0, 200 ], [ 0, 0 ] ].map { |x, y| coordinate(x, y) }
  end

  it "finds source-indexed circuits after an approach" do
    points = [ coordinate(-300, 0) ] + square + square.drop(1) + square.drop(1) + [ coordinate(-300, 0) ]
    candidates = described_class.new(points).call

    expect(candidates).to include(have_attributes(start_index: 1, end_index: 5))
    expect(candidates.first.coordinates).to eq(points[candidates.first.start_index..candidates.first.end_index])
    expect(candidates.first.coordinates).to be_frozen
  end

  it "uses the closest point of a visit, not the first point inside the radius" do
    circuit = square[0...-1] + [ coordinate(0, 20), coordinate(0, 3), coordinate(0, -20), coordinate(0, -50) ]
    candidate = described_class.new(circuit).call.find { |item| item.start_index.zero? }

    expect(candidate.end_index).to eq(5)
    expect(candidate.closure_distance_meters).to be_within(0.1).of(3)
  end

  it "rejects retraced out-and-backs" do
    points = [ coordinate(0, 0), coordinate(500, 0), coordinate(0, 0) ]

    expect(described_class.new(points).call).to be_empty
  end

  it "ignores short circuits and stationary samples" do
    points = Array.new(1_000) { coordinate(0, 0) } + [ coordinate(20, 0), coordinate(20, 20), coordinate(0, 0) ]

    expect(described_class.new(points).call).to be_empty
  end

  it "bounds geometric verification on a dense repeated track" do
    points = Array.new(1_000) { square }.flatten(1)
    allow(Allure::Geometry::Frechet).to receive(:distance).and_call_original

    expect(described_class.new(points).call.length).to be <= described_class::MAX_CANDIDATES
    expect(Allure::Geometry::Frechet).to have_received(:distance).at_most(described_class::MAX_CANDIDATES).times
  end

  it "keeps the distance scan linear through a long stationary recording" do
    points = Array.new(50_000) { coordinate(0, 0) }
    detector = described_class.new(points)
    allow(detector).to receive(:distance).and_call_original

    expect(detector.call).to be_empty
    expect(detector).to have_received(:distance).at_most(points.length * 3).times
  end
end
