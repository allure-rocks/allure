# frozen_string_literal: true

require "rails_helper"

# docs/dev/AI.md §3.3: the sections of a recorded route. Pure: every example
# feeds stored point hashes, never the database.
RSpec.describe Allure::Gpx::RouteProfile do
  let(:started_at) { Time.zone.parse("2026-11-17 09:00:00") }

  # A positioned segment from `[distance, seconds, elevation, heart_rate]`
  # rows; a nil elevation leaves the point without one, the way a missing
  # terrain sample is stored. The segment is a plain struct: the profile reads
  # points, not rows.
  def segment(rows, position: 0, started_at: self.started_at)
    points = rows.map do |distance, seconds, elevation, heart_rate|
      point = { "t" => seconds, "d" => distance, "lat" => 45.0 + (distance * 0.000009), "lon" => 6.0 }
      point["ele"] = elevation unless elevation.nil?
      point["hr"] = heart_rate if heart_rate
      point
    end
    build_segment(started_at:, position:, distance: rows.last[0].to_f, points:)
  end

  def build_segment(started_at:, position:, distance:, points:)
    Struct.new(:started_at, :position, :distance, :points).new(started_at, position, distance, points)
  end

  def profile(segments, boundaries:, grade_adjusted: false, threshold: 0.0)
    described_class.new(segments:, workout_started_at: started_at,
                        stopped_speed_threshold_km_h: threshold,
                        elevation_filter: "gps", grade_adjusted_pace: grade_adjusted).call(boundaries:)
  end

  # 10 km sampled every kilometre: 5:20/km on the first half, 5:40/km on the
  # second.
  def ten_k(elevations:, slow_second: true)
    rows = [ [ 0, 0, elevations[0] ] ]
    time = 0
    1.upto(10) do |index|
      time += index <= 5 ? 320 : (slow_second ? 340 : 320)
      rows << [ index * 1_000, time, elevations[index] ]
    end
    rows
  end

  let(:halves) { [ 0.0, 5_000.0, 10_000.0 ] }
  let(:climb_second) { [ 0, 4, 8, 12, 16, 20, 56, 92, 128, 164, 200 ] }
  let(:climb_first) { [ 0, 36, 72, 108, 144, 180, 180, 180, 180, 180, 180 ] }
  let(:flat) { Array.new(11, 100) }

  it "cuts at the given boundaries and measures each section" do
    result = profile([ segment(ten_k(elevations: climb_second)) ], boundaries: halves)

    expect(result.distance).to be_within(1).of(10_000)
    expect(result.sections.map { it.distance }).to all(be_within(1).of(5_000))
    expect(result.sections.first.average_speed).to be_within(0.01).of(1_000 / 320.0)
    expect(result.sections.last.average_speed).to be_within(0.01).of(1_000 / 340.0)
    expect(result.sections.map(&:start_distance)).to eq([ 0.0, 5_000.0 ])
    expect(result.sections.map(&:end_distance)).to eq([ 5_000.0, 10_000.0 ])
  end

  it "keeps the climbing of each section apart, whichever one climbs" do
    late = profile([ segment(ten_k(elevations: climb_second)) ], boundaries: halves)
    early = profile([ segment(ten_k(elevations: climb_first)) ], boundaries: halves)

    expect(late.sections.first.ascent).to be_within(1).of(20)
    expect(late.sections.last.ascent).to be_within(1).of(180)
    expect(early.sections.first.ascent).to be_within(1).of(180)
    expect(early.sections.last.ascent).to be_within(1).of(0)
  end

  it "splits an interval that straddles a boundary in proportion" do
    rows = [ [ 0, 0, 100 ], [ 5_000, 500, 100 ], [ 10_000, 1_000, 100 ] ]

    result = profile([ segment(rows) ], boundaries: [ 0.0, 3_000.0, 10_000.0 ])

    expect(result.sections.first.distance).to be_within(1).of(3_000)
    expect(result.sections.last.distance).to be_within(1).of(7_000)
    expect(result.sections.first.moving_time).to be_within(1).of(300)
    expect(result.sections.last.moving_time).to be_within(1).of(700)
  end

  it "keeps a section beyond the last boundary in the closing section" do
    result = profile([ segment(ten_k(elevations: flat)) ], boundaries: [ 0.0, 8_000.0 ])

    expect(result.sections.length).to eq(1)
    expect(result.sections.first.distance).to be_within(1).of(10_000)
  end

  it "keeps a stationary interval out of the moving time" do
    rows = ten_k(elevations: flat)
    stopped = [ 5_000, rows[5][1] + 600, 100 ]
    rows.insert(6, stopped)
    rows[7..].each { |row| row[1] += 600 }

    result = profile([ segment(rows) ], boundaries: halves)

    expect(result.sections.first.moving_time).to be_within(1).of(1_600)
    expect(result.sections.last.moving_time).to be_within(1).of(1_700)
    expect(result.distance).to be_within(1).of(10_000)
  end

  it "never bridges the gap between two recording segments" do
    first = segment([ [ 0, 0, 100 ], [ 2_000, 400, 150 ] ], position: 0)
    second = segment([ [ 0, 0, 500 ], [ 2_000, 400, 550 ] ], position: 1)

    result = profile([ first, second ], boundaries: [ 0.0, 2_000.0, 4_000.0 ])

    expect(result.distance).to be_within(1).of(4_000)
    # The boundaries follow the point stream's own offsets: the first climb
    # stays in the first section.
    expect(result.sections.first.ascent).to be_within(1).of(50)
    expect(result.sections.last.ascent).to be_within(1).of(50)
    expect(result.sections.sum { it.ascent }).to be_within(1).of(100)
  end

  it "reports missing elevation as missing, never as a flat section" do
    elevations = [ 100, 104, 108, 112, 116, 120, nil, nil, nil, nil, nil ]

    result = profile([ segment(ten_k(elevations:)) ], boundaries: halves)

    expect(result.sections.first.elevation_coverage).to eq(1.0)
    expect(result.sections.last.elevation_coverage).to eq(0.0)
    expect(result.sections.last.ascent).to eq(0.0)
    expect(result.sections.last.grade).to be_nil
  end

  it "averages the heart rate over the moving time" do
    rows = [ [ 0, 0, 100, 140 ], [ 1_000, 300, 100, 160 ], [ 2_000, 600, 100, 150 ] ]

    result = profile([ segment(rows) ], boundaries: [ 0.0, 1_500.0, 2_000.0 ])

    expect(result.sections.first.heart_rate).to eq(152)
    expect(result.sections.last.heart_rate).to eq(155)
  end

  it "leaves the heart rate empty without a sensor" do
    result = profile([ segment(ten_k(elevations: flat)) ], boundaries: halves)

    expect(result.sections.map(&:heart_rate)).to eq([ nil, nil ])
  end

  it "computes a grade-adjusted pace for the sports that ask for one" do
    result = profile([ segment(ten_k(elevations: climb_second)) ], boundaries: halves, grade_adjusted: true)

    expect(result.sections.first.grade_adjusted_pace).to be_present
    expect(result.sections.last.grade_adjusted_pace).to be_present
    # Climbing costs more than flat ground, so the flat-equivalent pace of the
    # climbing section is faster than its raw pace.
    expect(result.sections.last.grade_adjusted_pace).to be < result.sections.last.pace
    expect(result.sections.last.grade_adjusted_coverage).to be_within(0.01).of(1.0)
  end

  it "leaves the grade-adjusted pace out when the sport does not ask for one" do
    result = profile([ segment(ten_k(elevations: climb_second)) ], boundaries: halves)

    expect(result.sections.first.grade_adjusted_pace).to be_nil
  end

  it "measures the sections of a positionless recording without inventing terrain" do
    points = 0.upto(10).map { |index| { "t" => index * 300, "d" => index * 1_000 } }
    segment = build_segment(started_at:, position: 0, distance: 10_000.0, points:)

    result = profile([ segment ], boundaries: [ 0.0, 4_000.0, 10_000.0 ])

    expect(result.sections.first.distance).to be_within(1).of(4_000)
    expect(result.sections.first.elevation_coverage).to eq(0.0)
    expect(result.sections.first.grade_adjusted_coverage).to eq(0.0)
  end

  it "writes no profile without two boundaries" do
    expect(profile([ segment(ten_k(elevations: flat)) ], boundaries: [ 0.0 ])).to be_nil
  end

  it "writes no profile without a measurable track" do
    expect(profile([], boundaries: halves)).to be_nil
  end
end
