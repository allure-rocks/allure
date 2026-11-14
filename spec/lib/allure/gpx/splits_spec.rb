# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::Splits do
  SplitSegment = Data.define(:position, :started_at, :distance, :points)

  let(:started_at) { Time.utc(2026, 8, 27, 8, 0, 0) }

  it "interpolates exact kilometre crossings and retains the trailing partial" do
    segments = [ split_segment(distance: 2_500.0, started_at:, points: points(2_500, 2_500)) ]

    result = described_class.new(segments:, unit: :metric, workout_started_at: started_at).call

    expect(result.map(&:distance)).to eq([ 1_000.0, 1_000.0, 500.0 ])
    expect(result.map(&:elapsed_time)).to eq([ 1_000.0, 1_000.0, 500.0 ])
    expect(result.map(&:partial)).to eq([ false, false, true ])
  end

  it "uses a mile interval for imperial viewers" do
    segments = [ split_segment(distance: 2_000.0, started_at:, points: points(2_000, 2_000)) ]

    result = described_class.new(segments:, unit: :imperial, workout_started_at: started_at).call

    expect(result.first.distance).to be_within(0.001).of(1_609.344)
    expect(result.last.distance).to be_within(0.001).of(390.656)
    expect(result.last.partial).to be(true)
  end

  it "includes the elapsed recording gap in a split without joining geometry" do
    segments = [
      split_segment(distance: 1_500.0, started_at:, points: points(1_500, 1_500)),
      split_segment(distance: 1_000.0, started_at: started_at + 3_600, points: points(1_000, 1_000))
    ]

    result = described_class.new(segments:, unit: :metric, workout_started_at: started_at).call

    expect(result.map(&:distance)).to eq([ 1_000.0, 1_000.0, 500.0 ])
    expect(result[1].elapsed_time).to eq(3_100.0)
  end

  it "computes a grade-adjusted pace per split when enabled" do
    points = (0..10).map do |step|
      distance = step * 100.0
      { "t" => step * 100, "d" => distance, "lat" => 45.0 + (distance / 111_320.0), "lon" => 6.0, "ele" => 100.0 + (step * 5) }
    end
    segments = [ split_segment(distance: 1_100.0, started_at:, points:) ]

    result = described_class.new(
      segments:, unit: :metric, workout_started_at: started_at,
      stopped_speed_threshold_km_h: 0.5, grade_adjusted_pace: true
    ).call

    expect(result.map(&:grade_adjusted_pace)).to all(be_a(Integer))
    # The 5 % climb is faster than the flat-equivalent 1 000 s/km actual pace.
    expect(result.first.grade_adjusted_pace).to be < 1_000
  end

  it "leaves the grade-adjusted pace nil when disabled" do
    segments = [ split_segment(distance: 2_500.0, started_at:, points: points(2_500, 2_500)) ]

    result = described_class.new(segments:, unit: :metric, workout_started_at: started_at).call

    expect(result.map(&:grade_adjusted_pace)).to all(be_nil)
  end

  it "averages the power of each split's own points, and leaves it nil without power" do
    # The boundary point belongs to the split that ends there and to the one
    # that starts there, exactly as the elevation deltas are attributed.
    points = [
      point(0, 0.0).merge("pw" => 200),
      point(500, 500.0).merge("pw" => 220),
      point(1_000, 1_000.0),
      point(1_500, 1_500.0)
    ]
    segments = [ split_segment(distance: 1_500.0, started_at:, points:) ]

    result = described_class.new(segments:, unit: :metric, workout_started_at: started_at).call

    expect(result.map(&:average_power)).to eq([ 210, nil ])
  end

  it "attributes elevation gain and loss to the split that carries them" do
    points = [
      point(0, 0.0, 100.0),
      point(500, 500.0, 150.0),
      point(1_000, 1_000.0, 200.0),
      point(1_500, 1_500.0, 150.0),
      point(2_000, 2_000.0, 100.0)
    ]
    segments = [ split_segment(distance: 2_000.0, started_at:, points:) ]

    result = described_class.new(segments:, unit: :metric, workout_started_at: started_at).call

    expect(result.map(&:ascent)).to eq([ 100.0, 0.0 ])
    expect(result.map(&:descent)).to eq([ 0.0, 100.0 ])
    expect(result.sum(&:ascent) + result.sum(&:descent)).to eq(200.0)
  end

  private

  def split_segment(distance:, started_at:, points:)
    SplitSegment.new(position: 0, started_at:, distance:, points:)
  end

  def points(distance, final_time)
    [
      point(0, 0.0),
      point(final_time / 2, distance / 2),
      point(final_time, distance)
    ]
  end

  def point(time, distance, elevation = nil)
    { "t" => time, "d" => distance, "lat" => 45.0, "lon" => 6.0 }.tap do |hash|
      hash["ele"] = elevation if elevation
    end
  end
end
