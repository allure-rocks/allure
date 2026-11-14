# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Laps::DescentDetector do
  def points_for(elevations, power: nil)
    start = Time.zone.parse("2026-08-23 06:00:00")
    elevations.each_with_index.map do |elevation, index|
      Allure::Segments::Point.new(
        index:,
        segment_index: 0,
        segment_point_index: index,
        time: start + (index * 60),
        elapsed_time: index * 60,
        distance: index * 100.0,
        longitude: 6.4,
        latitude: 45.0,
        elevation:,
        speed: 1.7,
        heart_rate: 140,
        cadence: 80,
        power:
      )
    end
  end

  def descent_elevations
    (0..22).map do |index|
      distance = index * 100.0
      case distance
      when 0...600 then 200.0
      when 600..1_600 then 200.0 - ((distance - 600.0) * 0.1)
      else 100.0
      end
    end
  end

  it "detects a sustained descent from the inverted profile" do
    descents = described_class.new(points: points_for(descent_elevations)).call

    expect(descents.length).to eq(1)
    descent = descents.first
    expect(descent.source).to eq("descent")
    expect(descent.start_point_index).to be_between(5, 6)
    expect(descent.end_point_index).to eq(16)
    expect(descent.distance).to be_within(110.0).of(1_050.0)
    expect(descent.descent).to be_within(15.0).of(100.0)
    expect(descent.ascent).to be < 15.0
    expect(descent.average_grade).to be_within(1.0).of(9.5)
    expect(descent.elapsed_time).to be_between(600, 660)
  end

  it "detects a long alpine descent in one piece" do
    elevations = Array.new(10, 1_800.0) + (1..200).map { 1_800.0 - (it * 5.0) } + Array.new(10, 800.0)

    descents = described_class.new(points: points_for(elevations)).call

    expect(descents.length).to eq(1)
    expect(descents.first.distance).to be_within(300.0).of(20_000.0)
    expect(descents.first.descent).to be_within(30.0).of(1_000.0)
  end

  it "returns nothing for a flat profile" do
    expect(described_class.new(points: points_for(Array.new(23, 100.0))).call).to be_empty
  end

  it "never counts a teleport between two recording segments as a descent" do
    start = Time.zone.parse("2026-08-23 06:00:00")
    points = [ [ Array.new(20, 100.0), [ 45.0, 6.4 ] ], [ Array.new(20, 10.0), [ 45.1, 6.5 ] ] ]
      .each_with_index.flat_map do |(elevations, (latitude, longitude)), segment_index|
        elevations.each_with_index.map do |elevation, position|
          global = (segment_index * 20) + position
          Allure::Segments::Point.new(
            index: global, segment_index:, segment_point_index: position,
            time: start + (global * 60), elapsed_time: global * 60,
            distance: (segment_index * 2_000.0) + (position * 100.0),
            longitude: longitude + (position * 0.0001), latitude:,
            elevation:, speed: 1.7, heart_rate: 140, cadence: 80, power: nil
          )
        end
      end

    expect(described_class.new(points:).call).to be_empty
  end

  it "returns nothing without elevation" do
    expect(described_class.new(points: points_for(Array.new(23))).call).to be_empty
  end
end
