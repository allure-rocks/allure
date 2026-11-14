# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Laps::PowerIntervalDetector do
  def points_for(powers)
    start = Time.zone.parse("2026-08-23 06:00:00")
    distance = 0.0
    points = [ build_point(0, start, distance, powers.first) ]
    powers.each_with_index do |power, index|
      distance += 50.0
      points << build_point(index + 1, start + ((index + 1) * 10), distance, power)
    end
    points
  end

  def build_point(index, time, distance, power)
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
      speed: 5.0,
      heart_rate: 140,
      cadence: 80,
      power:
    )
  end

  def interval_pattern
    (Array.new(60, 100.0) + Array.new(60, 300.0) + Array.new(60, 100.0))
  end

  it "detects a sustained power block" do
    intervals = described_class.new(points: points_for(interval_pattern), colour_group: "ride").call

    expect(intervals.length).to eq(1)
    interval = intervals.first
    expect(interval.source).to eq("power_interval")
    expect(interval.distance).to be_within(100.0).of(3_000.0)
    expect(interval.average_power).to be_within(20).of(300)
    expect(interval.max_power).to eq(300)
  end

  it "returns nothing for a steady endurance ride" do
    intervals = described_class.new(points: points_for(Array.new(180, 100.0)), colour_group: "ride").call

    expect(intervals).to be_empty
  end

  it "returns nothing without a power profile" do
    expect(described_class.new(points: points_for(interval_pattern), colour_group: "hike").call).to be_empty
  end
end
