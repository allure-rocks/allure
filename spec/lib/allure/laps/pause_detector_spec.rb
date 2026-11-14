# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Laps::PauseDetector do
  it "returns nothing for a single uninterrupted recording" do
    workout = create(:workout)
    create(:track_segment, workout:)

    expect(described_class.new(segments: workout.track_segments).call).to be_empty
  end

  it "creates one lap per recording segment with global indexes and distances" do
    workout = create(:workout)
    first = create(:track_segment, workout:, position: 0)
    second = create(:track_segment, workout:, position: 1,
      started_at: workout.started_at + 120.seconds,
      points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.0728, "lon" => 6.4092, "ele" => 112.0 },
        { "t" => 90, "d" => 300.0, "lat" => 45.0746, "lon" => 6.4110, "ele" => 118.0 }
      ],
      distance: 300.0, duration: 90, moving_time: 80, pause_time: 10)

    laps = described_class.new(segments: workout.track_segments).call

    expect(laps.length).to eq(2)
    expect(laps.first).to have_attributes(
      source: "pause",
      start_point_index: 0,
      end_point_index: 1,
      start_distance: 0.0,
      end_distance: 250.0,
      elapsed_time: first.duration,
      started_at: first.started_at
    )
    expect(laps.last).to have_attributes(
      start_point_index: 2,
      end_point_index: 3,
      start_distance: 250.0,
      end_distance: 550.0,
      elapsed_time: 90,
      started_at: workout.started_at + 120.seconds
    )
  end

  it "skips a zero-distance recording segment" do
    workout = create(:workout)
    create(:track_segment, workout:, position: 0)
    create(:track_segment, workout:, position: 1, distance: 0.0,
      points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.0728, "lon" => 6.4092, "ele" => 112.0 },
        { "t" => 30, "d" => 0.0, "lat" => 45.0728, "lon" => 6.4092, "ele" => 112.0 }
      ],
      duration: 30, moving_time: 0, pause_time: 30, ascent: 0.0, descent: 0.0, average_speed: 0.0)

    laps = described_class.new(segments: workout.track_segments).call

    expect(laps.length).to eq(1)
    expect(laps.first.start_point_index).to eq(0)
  end
end
