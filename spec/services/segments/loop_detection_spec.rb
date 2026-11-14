# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::LoopDetection do
  let(:workout) { create(:workout) }

  def square(side = 200, x = 0)
    [ [ x, 0 ], [ x + side, 0 ], [ x + side, side ], [ x, side ], [ x, 0 ] ]
  end

  def stream(coordinates, segment_index: 0, index_offset: 0, distance_offset: 0)
    distance = distance_offset.to_f
    coordinates.each_with_index.map do |(x, y), index|
      distance += Math.hypot(x - coordinates[index - 1][0], y - coordinates[index - 1][1]) if index.positive?
      Allure::Segments::Point.new(
        index: index + index_offset, segment_index:, segment_point_index: index,
        time: workout.started_at + distance / 3, elapsed_time: distance / 3, distance:,
        longitude: x / 111_319.49, latitude: y / 111_319.49,
        elevation: nil, speed: nil, heart_rate: nil, cadence: nil, power: nil
      )
    end
  end

  def detect(coordinates)
    described_class.new(workout:, points: stream(coordinates)).call
  end

  it "excludes an approach, return and incomplete tours" do
    coordinates = [ [ -300, 200 ] ] + square.last(2) + square.drop(1) + square.drop(1) + [ square[1], [ 500, 0 ] ]
    result = detect(coordinates)

    expect(result.matches.length).to eq(2)
    expect(result.matches.map(&:distance)).to all(be_within(1).of(800))
    expect(result.matches.first.start_point_index).to be > 0
    expect(result.matches.last.end_point_index).to be < coordinates.length - 1
  end

  it "accepts ordinary GPS variation between tours" do
    jittered = square.map { |x, y| [ x + 3, y + 2 ] }
    result = detect([ [ -300, 0 ] ] + square + jittered + square)

    expect(result.matches.length).to eq(3)
  end

  it "does not count an opposite-direction traversal as a second tour" do
    expect(detect(square + square.reverse.drop(1))).to be_nil
  end

  it "does not mistake distinct circuits sharing a crossing for repetitions" do
    expect(detect(square + square(500).drop(1))).to be_nil
  end

  it "continues past an isolated circuit to a repeated circuit later in the recording" do
    result = detect(square + square(300, 2_000) + square(300, 2_000).drop(1))

    expect(result.matches.length).to eq(2)
    expect(result.candidate.start_index).to be >= square.length
    expect(result.matches.map(&:distance)).to all(be_within(1).of(1_200))
  end

  it "keeps only complete tours while allowing repetitions in separate recording segments" do
    first = stream(square)
    second = stream(square, segment_index: 1, index_offset: first.length, distance_offset: 800)
    result = described_class.new(workout:, points: first + second).call

    expect(result.matches.length).to eq(2)
    expect(result.matches.map(&:distance)).to all(be_within(1).of(800))
  end

  it "chooses the circuit with the largest validated coverage" do
    result = detect(square + square.drop(1) + square(400, 2_000) + square(400, 2_000).drop(1))

    expect(result.matches.length).to eq(2)
    expect(result.matches.map(&:distance)).to all(be_within(1).of(1_600))
  end

  it "never persists speculative candidates" do
    expect { detect(square) }.not_to change(Segment, :count)
  end
end
