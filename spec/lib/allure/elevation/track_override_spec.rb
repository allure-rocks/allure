# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Elevation::TrackOverride do
  def point_at(distance, latitude: 0.0, **attributes)
    longitude = distance / Allure::Gpx::Geo::EARTH_RADIUS_METRES * 180.0 / Math::PI
    Allure::Gpx::Point.new(time: distance, latitude:, longitude:, **attributes)
  end

  def track(points:, **attributes)
    Allure::Gpx::Track.new(
      creator: "Garmin",
      name: "Sortie",
      description: "description",
      calories: 500,
      source_max_speed: 12.0,
      activity_signals: [ :running ],
      segments: [ Allure::Gpx::Segment.new(points:) ],
      laps: [],
      **attributes
    )
  end

  it "replaces every elevation with the profile value at its distance" do
    source = track(points: [ point_at(0), point_at(500), point_at(1000) ])
    profile = Allure::Elevation::Profile.new([
      { distance: 0.0, elevation: 100.0 },
      { distance: 1000.0, elevation: 200.0 }
    ])

    result = described_class.call(source, profile:)
    elevations = result.segments.first.points.map(&:elevation)

    expect(elevations[0]).to eq(100.0)
    expect(elevations[1]).to be_within(0.01).of(150.0)
    expect(elevations[2]).to eq(200.0)
  end

  it "leaves a point without profile coverage without an elevation" do
    source = track(points: [ point_at(0, elevation: 42.0), point_at(500), point_at(1000) ])
    profile = Allure::Elevation::Profile.new([
      { distance: 0.0, elevation: 100.0 },
      { distance: 500.0, elevation: nil },
      { distance: 1000.0, elevation: 200.0 }
    ])

    result = described_class.call(source, profile:)

    expect(result.segments.first.points.map(&:elevation)).to eq([ 100.0, nil, 200.0 ])
  end

  it "keeps the track metadata and every non-elevation attribute" do
    source = track(points: [ point_at(0, heart_rate: 120, cadence: 80, power: 200) ])
    profile = Allure::Elevation::Profile.new([ { distance: 0.0, elevation: 100.0 } ])

    result = described_class.call(source, profile:)
    result_point = result.segments.first.points.first

    expect(result).to have_attributes(
      creator: "Garmin", name: "Sortie", description: "description",
      calories: 500, source_max_speed: 12.0, activity_signals: [ :running ], laps: []
    )
    expect(result_point).to have_attributes(
      time: 0, latitude: 0.0, longitude: 0.0, heart_rate: 120, cadence: 80, power: 200
    )
  end

  it "reuses unchanged points and never mutates the source track" do
    source_point = point_at(0, elevation: 100.0)
    source = track(points: [ source_point ])
    profile = Allure::Elevation::Profile.new([ { distance: 0.0, elevation: 100.0 } ])

    result = described_class.call(source, profile:)

    expect(result.segments.first.points.first).to be(source_point)
    expect(source.segments.first.points.first.elevation).to eq(100.0)
  end
end
