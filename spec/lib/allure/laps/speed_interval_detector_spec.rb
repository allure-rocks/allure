# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Laps::SpeedIntervalDetector do
  def points_for(speeds)
    start = Time.zone.parse("2026-08-23 06:00:00")
    distance = 0.0
    points = [ build_point(0, start, distance) ]
    speeds.each_with_index do |speed, index|
      distance += speed * 10.0
      points << build_point(index + 1, start + ((index + 1) * 10), distance)
    end
    points
  end

  def build_point(index, time, distance)
    Allure::Segments::Point.new(
      index:,
      segment_index: 0,
      segment_point_index: index,
      time:,
      elapsed_time: time - Time.zone.parse("2026-08-23 06:00:00"),
      distance:,
      longitude: 6.4,
      latitude: 45.0,
      elevation: 100.0,
      speed: nil,
      heart_rate: 140,
      cadence: 80,
      power: nil
    )
  end

  def interval_pattern
    (Array.new(60, 2.0) + Array.new(60, 8.0) + Array.new(60, 2.0))
  end

  it "detects a sustained fast block" do
    intervals = described_class.new(points: points_for(interval_pattern), colour_group: "run").call

    expect(intervals.length).to eq(1)
    interval = intervals.first
    expect(interval.source).to eq("speed_interval")
    expect(interval.distance).to be_within(320.0).of(4_800.0)
    expect(interval.elapsed_time).to be_within(20).of(600)
    expect(interval.average_speed).to be_within(0.5).of(8.0)
  end

  it "returns nothing for a constant easy effort" do
    intervals = described_class.new(points: points_for(Array.new(180, 2.0)), colour_group: "run").call

    expect(intervals).to be_empty
  end

  it "returns nothing with too few samples" do
    expect(described_class.new(points: points_for(Array.new(10, 8.0)), colour_group: "run").call).to be_empty
  end
end
