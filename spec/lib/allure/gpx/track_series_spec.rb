# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::TrackSeries do
  # A recording segment reduced to what both series read. Deliberately not the
  # TrackSegment model: this class operates on values and must stay usable
  # without Active Record.
  recording_segment = Struct.new(:started_at, :distance, :points)

  define_method(:segment) do |points:, distance:, started_at: Time.zone.parse("2026-01-01 10:00:00")|
    recording_segment.new(started_at, distance, points)
  end

  def point(distance:, time: 0, lon: 6.4, lat: 45.0, elevation: nil, speed: nil, power: nil)
    {
      "d" => distance, "t" => time, "lon" => lon, "lat" => lat
    }.tap do |value|
      value["ele"] = elevation unless elevation.nil?
      value["v"] = speed unless speed.nil?
      value["pw"] = power unless power.nil?
    end
  end

  it "emits one Feature per recording segment so a pause draws no connecting line" do
    segments = [
      segment(distance: 100.0, points: [ point(distance: 0.0, lon: 6.40, lat: 45.00),
                                         point(distance: 100.0, lon: 6.41, lat: 45.01) ]),
      segment(distance: 50.0, points: [ point(distance: 0.0, lon: 6.50, lat: 45.10),
                                        point(distance: 50.0, lon: 6.51, lat: 45.11) ])
    ]

    result = described_class.new(segments:).call

    expect(result[:type]).to eq("FeatureCollection")
    expect(result[:features].length).to eq(2)
    expect(result[:features].map { it[:geometry][:type] }).to all(eq("LineString"))
    expect(result[:features].map { it[:properties][:segment_index] }).to eq([ 0, 1 ])
  end

  it "keeps GeoJSON [longitude, latitude] order" do
    segments = [ segment(distance: 10.0, points: [ point(distance: 0.0, lon: 6.4074, lat: 45.0710),
                                                   point(distance: 10.0, lon: 6.4092, lat: 45.0728) ]) ]

    coordinates = described_class.new(segments:).call[:features].first[:geometry][:coordinates]

    expect(coordinates).to eq([ [ 6.4074, 45.0710 ], [ 6.4092, 45.0728 ] ])
  end

  it "reports distance cumulatively across segments rather than restarting each one" do
    segments = [
      segment(distance: 100.0, points: [ point(distance: 0.0), point(distance: 100.0) ]),
      segment(distance: 250.0, points: [ point(distance: 0.0), point(distance: 250.0) ]),
      segment(distance: 30.0, points: [ point(distance: 0.0), point(distance: 30.0) ])
    ]

    distances = described_class.new(segments:).call[:features].map { it[:properties][:distance] }

    expect(distances).to eq([ [ 0.0, 100.0 ], [ 100.0, 350.0 ], [ 350.0, 380.0 ] ])
  end

  describe "metrics" do
    it "carries elevation and speed as arrays aligned with the coordinates" do
      segments = [ segment(distance: 10.0, points: [
        point(distance: 0.0, elevation: 100.0, speed: 2.5),
        point(distance: 10.0, elevation: 112.5, speed: 3.0)
      ]) ]

      properties = described_class.new(segments:).call[:features].first[:properties]

      expect(properties[:elevation]).to eq([ 100.0, 112.5 ])
      expect(properties[:speed]).to eq([ 2.5, 3.0 ])
    end

    it "carries power as an array aligned with the coordinates" do
      segments = [ segment(distance: 10.0, points: [
        point(distance: 0.0, power: 200),
        point(distance: 10.0, power: 0)
      ]) ]

      properties = described_class.new(segments:).call[:features].first[:properties]

      expect(properties[:power]).to eq([ 200, 0 ])
    end

    it "omits a metric absent from every point instead of sending an array of nulls" do
      segments = [ segment(distance: 10.0, points: [ point(distance: 0.0), point(distance: 10.0) ]) ]

      properties = described_class.new(segments:).call[:features].first[:properties]

      expect(properties).not_to have_key(:elevation)
      expect(properties).not_to have_key(:speed)
      expect(properties).not_to have_key(:power)
      expect(properties).to have_key(:distance)
    end

    it "keeps a partially recorded metric, with nulls where it is missing" do
      segments = [ segment(distance: 10.0, points: [
        point(distance: 0.0, elevation: 100.0),
        point(distance: 5.0),
        point(distance: 10.0, elevation: 90.0)
      ]) ]

      expect(described_class.new(segments:).call[:features].first[:properties][:elevation])
        .to eq([ 100.0, nil, 90.0 ])
    end

    it "keeps a zero elevation, which is a reading rather than a missing value" do
      segments = [ segment(distance: 10.0, points: [
        point(distance: 0.0, elevation: 0.0), point(distance: 10.0, elevation: 0.0)
      ]) ]

      expect(described_class.new(segments:).call[:features].first[:properties][:elevation])
        .to eq([ 0.0, 0.0 ])
    end
  end

  it "agrees with ChartSeries on cumulative distance, which hover synchronisation relies on" do
    started_at = Time.zone.parse("2026-01-01 10:00:00")
    segments = [
      segment(distance: 120.0, started_at:,
              points: [ point(distance: 0.0, time: 0, elevation: 10.0),
                        point(distance: 120.0, time: 60, elevation: 20.0) ]),
      segment(distance: 80.0, started_at: started_at + 10.minutes,
              points: [ point(distance: 0.0, time: 0, elevation: 20.0),
                        point(distance: 80.0, time: 45, elevation: 30.0) ])
    ]

    track = described_class.new(segments:).call
    chart = Allure::Gpx::ChartSeries.new(workout_started_at: started_at, segments:).call

    expect(track[:features].flat_map { it[:properties][:distance] })
      .to eq(chart.map { it[:distance] })
  end
end
