# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Laps::StopDetector do
  def moving_point(index, time, distance, segment_index: 0)
    Allure::Segments::Point.new(
      index:,
      segment_index:,
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

  def stop_points
    start = Time.zone.parse("2026-08-23 06:00:00")
    points = []
    distance = 0.0
    index = 0
    6.times do
      points << moving_point(index, start + (index * 10), distance)
      distance += 30.0
      index += 1
    end
    6.times do
      points << moving_point(index, start + (index * 10), 150.0)
      index += 1
    end
    6.times do
      distance += 30.0
      points << moving_point(index, start + (index * 10), distance)
      index += 1
    end
    points
  end

  it "detects a sustained stop inside one recording segment" do
    stops = described_class.new(points: stop_points, stopped_speed_threshold_km_h: 1.0).call

    expect(stops.length).to eq(1)
    stop = stops.first
    expect(stop.source).to eq("stop")
    expect(stop.elapsed_time).to eq(60)
    expect(stop.distance).to eq(0.0)
    expect(stop.moving_time).to eq(0)
  end

  it "does not report a moving block" do
    points = stop_points.first(6)

    expect(described_class.new(points:, stopped_speed_threshold_km_h: 1.0).call).to be_empty
  end

  it "splits a stop at a recording gap" do
    start = Time.zone.parse("2026-08-23 06:00:00")
    first = (0..6).map { |index| moving_point(index, start + (index * 10), 0.0) }
    second = (0..6).map { |index| moving_point(index + 7, start + 60 + (index * 10), 0.0, segment_index: 1) }

    stops = described_class.new(points: first + second, stopped_speed_threshold_km_h: 1.0).call

    expect(stops.length).to eq(2)
    expect(stops.map(&:elapsed_time)).to eq([ 60, 60 ])
  end
end
