# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::DeviceElevationTotals do
  let(:start) { Time.utc(2026, 5, 1, 8, 0, 0) }

  def track_for(session_ascent: nil, session_descent: nil, laps: [])
    parse_fit(build_fit(points: simple_fit_points(start:), sport: 2, session_ascent:, session_descent:, laps:))
  end

  def lap(index, distance:, ascent: nil, descent: nil)
    { time: start + (index * 60), elapsed: 60, distance:, ascent:, descent: }
  end

  it "prefers complete recorded laps over the session totals" do
    track = track_for(
      session_ascent: 332,
      session_descent: 333,
      laps: [ lap(1, distance: 1000, ascent: 123, descent: 45) ]
    )

    expect(described_class.call(track:, distance: 1000)).to eq(ascent: 123.0, descent: 45.0)
  end

  it "falls back to the session totals when the laps do not cover the activity" do
    track = track_for(
      session_ascent: 123,
      session_descent: 45,
      laps: [ lap(1, distance: 500, ascent: 10, descent: 5) ]
    )

    expect(described_class.call(track:, distance: 1000)).to eq(ascent: 123.0, descent: 45.0)
  end

  it "sums the recorded laps when the session carries no totals" do
    track = track_for(laps: [
      lap(1, distance: 600, ascent: 10, descent: 5),
      lap(2, distance: 400, ascent: 20, descent: 8)
    ])

    expect(described_class.call(track:, distance: 1000)).to eq(ascent: 30.0, descent: 13.0)
  end

  it "skips a trailing partial lap and still accepts the covered total" do
    track = track_for(laps: [
      lap(1, distance: 960, ascent: 10, descent: 5),
      lap(2, distance: 40)
    ])

    expect(described_class.call(track:, distance: 1000)).to eq(ascent: 10.0, descent: 5.0)
  end

  it "refuses laps that do not cover the activity" do
    track = track_for(laps: [
      lap(1, distance: 500, ascent: 10, descent: 5),
      lap(2, distance: 100, ascent: 10, descent: 5)
    ])

    expect(described_class.call(track:, distance: 1000)).to be_nil
  end

  it "ignores the totals of a rendered world" do
    track = track_for(
      session_ascent: 80,
      session_descent: 0,
      laps: [ lap(1, distance: 1000, ascent: 0, descent: 0) ]
    )

    expect(described_class.call(track:, distance: 1000, virtual: true)).to be_nil
  end

  it "accepts a flat zero total" do
    track = track_for(session_ascent: 0, session_descent: 0)

    expect(described_class.call(track:, distance: 300)).to eq(ascent: 0.0, descent: 0.0)
  end

  it "returns nil without session totals or usable laps" do
    expect(described_class.call(track: track_for, distance: 300)).to be_nil
    expect(described_class.call(track: track_for(laps: [ lap(1, distance: 300) ]), distance: 300)).to be_nil
  end
end
