# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Laps::ClimbDetector do
  def points_for(elevations)
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
        power: 200
      )
    end
  end

  def climb_elevations
    (0..22).map do |index|
      distance = index * 100.0
      case distance
      when 0...600 then 100.0
      when 600..1_600 then 100.0 + ((distance - 600.0) * 0.1)
      when 1_600..2_000 then 200.0 - ((distance - 1_600.0) * 0.05)
      else 180.0
      end
    end
  end

  # Two recording segments, each 100 m between points. `second_origin` is where
  # the second segment starts: the first segment's end (a pause) or far away (a
  # teleport).
  def two_segment_points(first_elevations, second_elevations, second_origin:)
    start = Time.zone.parse("2026-08-23 06:00:00")
    offset = 0.0
    index = 0

    [ first_elevations, second_elevations ].each_with_index.flat_map do |elevations, segment_index|
      latitude, longitude = segment_index.zero? ? [ 45.0, 6.4 ] : second_origin
      points = elevations.each_with_index.map do |elevation, position|
        Allure::Segments::Point.new(
          index: index + position,
          segment_index:,
          segment_point_index: position,
          time: start + ((index + position) * 60),
          elapsed_time: (index + position) * 60,
          distance: offset + (position * 100.0),
          longitude: longitude + (position * 0.0001),
          latitude:,
          elevation:,
          speed: 1.7,
          heart_rate: 140,
          cadence: 80,
          power: 200
        )
      end
      offset += elevations.length * 100.0
      index += elevations.length
      points
    end
  end

  it "detects a sustained climb with grade, score, and slice metrics" do
    climbs = described_class.new(points: points_for(climb_elevations)).call

    expect(climbs.length).to eq(1)
    climb = climbs.first
    expect(climb.source).to eq("climb")
    expect(climb.start_point_index).to be_between(5, 6)
    expect(climb.end_point_index).to eq(16)
    expect(climb.distance).to be_within(110.0).of(1_050.0)
    expect(climb.ascent).to be_within(15.0).of(100.0)
    expect(climb.average_grade).to be_within(1.5).of(9.5)
    expect(climb.max_grade).to be > climb.average_grade
    expect(climb.climb_score).to be_positive
    expect(climb.elapsed_time).to eq(660)
  end

  it "keeps a climb in one piece across a sparse sample inside a segment" do
    # 300 m between points is a sparse sample, not a discontinuity: only a
    # segment boundary can break the profile.
    start = Time.zone.parse("2026-08-23 06:00:00")
    points = (0..20).map do |index|
      Allure::Segments::Point.new(
        index:,
        segment_index: 0,
        segment_point_index: index,
        time: start + (index * 60),
        elapsed_time: index * 60,
        distance: index * 300.0,
        longitude: 6.4 + (index * 0.003),
        latitude: 45.0,
        elevation: 100.0 + (index * 15),
        speed: 5.0,
        heart_rate: 140,
        cadence: 80,
        power: 200
      )
    end

    climbs = described_class.new(points:).call

    expect(climbs.length).to eq(1)
    expect(climbs.first.ascent).to be > 250.0
  end

  it "never counts a teleport between two recording segments as a climb" do
    # A flat run, then the platform moves the athlete back to the start, higher
    # up: the jump is not ground, so neither segment holds a climb.
    points = two_segment_points(
      Array.new(20, 100.0), (190..209).map(&:to_f), second_origin: [ 45.1, 6.5 ]
    )

    expect(described_class.new(points:).call).to be_empty
  end

  it "keeps a climb that spans a pause, where the ground is continuous" do
    points = two_segment_points(
      (0..9).map { |index| 100.0 + (index * 5) },
      (0..29).map { |index| 150.0 + (index * 5) },
      second_origin: [ 45.0, 6.4 ]
    )

    climbs = described_class.new(points:).call

    expect(climbs.length).to eq(1)
    expect(climbs.first.ascent).to be > 150.0
    expect(climbs.first.end_point_index).to eq(39)
  end

  it "returns nothing without elevation" do
    points = points_for([ nil, nil, nil, nil, nil ])

    expect(described_class.new(points:).call).to be_empty
  end

  it "returns nothing for a flat profile" do
    points = points_for(Array.new(23, 100.0))

    expect(described_class.new(points:).call).to be_empty
  end
end
