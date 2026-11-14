# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Laps::Metrics do
  def points_for(elevations:, seconds: 100)
    start = Time.zone.parse("2026-08-23 06:00:00")
    distance = 0.0
    elevations.each_with_index.map do |elevation, index|
      point = Allure::Segments::Point.new(
        index:,
        segment_index: 0,
        segment_point_index: index,
        time: start + (index * seconds),
        elapsed_time: index * seconds,
        distance:,
        longitude: 6.0,
        latitude: 45.0 + (distance / 111_320.0),
        elevation:,
        speed: nil,
        heart_rate: nil,
        cadence: nil,
        power: nil
      )
      distance += 100.0
      point
    end
  end

  it "computes a grade-adjusted pace when enabled" do
    points = points_for(elevations: [ 100.0, 105.0, 110.0, 115.0 ])
    result = described_class.new(points:, stopped_speed_threshold_km_h: 0.5, grade_adjusted_pace: true).call

    expect(result.grade_adjusted_pace).to be_a(Integer)
    expect(result.grade_adjusted_pace).to be < result.average_pace
  end

  it "leaves the grade-adjusted pace nil when disabled" do
    points = points_for(elevations: [ 100.0, 105.0, 110.0, 115.0 ])
    result = described_class.new(points:, stopped_speed_threshold_km_h: 0.5).call

    expect(result.grade_adjusted_pace).to be_nil
  end
end
