# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::ChartSeries do
  ChartSegment = Data.define(:started_at, :distance, :points)

  let(:started_at) { Time.utc(2026, 6, 1, 8, 0, 0) }

  it "builds workout-cumulative distance and elapsed time across segment gaps" do
    segments = [
      segment(started_at:, distance: 250.0, points: [ point(0, 0.0, 100.0), point(60, 250.0, 110.0) ]),
      segment(started_at: started_at + 180, distance: 100.0, points: [ point(0, 0.0, 120.0), point(30, 100.0, 125.0) ])
    ]

    expect(series(segments)).to eq(
      [
        { distance: 0.0, elapsed_time: 0, elevation: 100.0 },
        { distance: 250.0, elapsed_time: 60, elevation: 110.0 },
        { distance: 250.0, elapsed_time: 180, elevation: 120.0 },
        { distance: 350.0, elapsed_time: 210, elevation: 125.0 }
      ]
    )
  end

  it "retains zero elevation and represents missing elevation as nil" do
    points = [ point(0, 0.0, 0.0), point(10, 10.0, nil) ]

    expect(series([ segment(started_at:, distance: 10.0, points:) ]).pluck(:elevation)).to eq([ 0.0, nil ])
  end

  it "extracts aligned optional sensor series without coordinates" do
    points = [
      point(0, 0.0, 0.0, speed: 0.0, heart_rate: 140, cadence: 80, power: 200),
      point(10, 10.0, nil)
    ]

    result = series(
      [ segment(started_at:, distance: 10.0, points:) ],
      requested_series: Allure::Gpx::ChartSeries::SERIES_KEYS.keys
    )

    expect(result).to eq(
      [
        { distance: 0.0, elapsed_time: 0, elevation: 0.0, speed: 0.0, heart_rate: 140, cadence: 80, power: 200,
          device_temperature: nil },
        { distance: 10.0, elapsed_time: 10, elevation: nil, speed: nil, heart_rate: nil, cadence: nil, power: nil,
          device_temperature: nil }
      ]
    )
  end

  it "deterministically bounds large series while preserving endpoints, extrema, and gaps" do
    points = 1_200.times.map { point(it, it.to_f, 100.0 + (it % 20)) }
    points[123][Allure::Gpx::PointSerializer::KEY_ELEVATION] = -50.0
    points[500].delete(Allure::Gpx::PointSerializer::KEY_ELEVATION)
    points[876][Allure::Gpx::PointSerializer::KEY_ELEVATION] = 500.0
    segment = segment(started_at:, distance: 1_199.0, points:)

    first = series([ segment ])
    second = series([ segment ])

    expect(first).to eq(second)
    expect(first.length).to eq(1_000)
    expect(first.first[:distance]).to eq(0.0)
    expect(first.last[:distance]).to eq(1_199.0)
    expect(first).to include(
      a_hash_including(elevation: -50.0),
      a_hash_including(elevation: 500.0),
      a_hash_including(elevation: nil)
    )
    expect(first.pluck(:distance)).to eq(first.pluck(:distance).sort)
  end

  it "preserves extrema and both boundaries of null runs for every requested series" do
    values = [ 10, 11, 1, nil, nil, 12, 99, 13, nil, 15 ]

    Allure::Gpx::ChartSeries::SERIES_KEYS.each do |metric, source_key|
      points = values.each_with_index.map do |value, index|
        point(index, index.to_f, 50.0).tap { |entry| value.nil? ? entry.delete(source_key) : entry[source_key] = value }
      end
      result = series(
        [ segment(started_at:, distance: 9.0, points:) ],
        max_points: 7,
        requested_series: [ metric ]
      )

      expect(result.length).to eq(7)
      expect(result.pluck(:distance)).to eq([ 0.0, 2.0, 3.0, 5.0, 6.0, 8.0, 9.0 ])
      expect(result.find { |entry| entry[:distance] == 2.0 }.fetch(metric)).to eq(1)
      expect(result.find { |entry| entry[:distance] == 6.0 }.fetch(metric)).to eq(99)
      expect(result.find { |entry| entry[:distance] == 3.0 }.fetch(metric)).to be_nil
      expect(result.find { |entry| entry[:distance] == 5.0 }.fetch(metric)).to eq(12)
      expect(result.find { |entry| entry[:distance] == 8.0 }.fetch(metric)).to be_nil
    end
  end

  it "bounds pre-extracted points without any segment input" do
    points = [
      { distance: 0.0, elevation: 10.0 },
      { distance: 1.0, elevation: 99.0 },
      { distance: 2.0, elevation: 12.0 },
      { distance: 3.0, elevation: 11.0 },
      { distance: 4.0, elevation: 13.0 }
    ]

    result = described_class.new(points:, series: [ :elevation ], max_points: 4).call

    expect(result).to eq(
      [
        { distance: 0.0, elevation: 10.0 },
        { distance: 1.0, elevation: 99.0 },
        { distance: 2.0, elevation: 12.0 },
        { distance: 4.0, elevation: 13.0 }
      ]
    )
  end

  private

  def series(segments, max_points: described_class::MAX_POINTS, requested_series: [ :elevation ])
    described_class.new(workout_started_at: started_at, segments:, max_points:, series: requested_series).call
  end

  def segment(started_at:, distance:, points:)
    ChartSegment.new(started_at:, distance:, points:)
  end

  def point(time, distance, elevation, speed: nil, heart_rate: nil, cadence: nil, power: nil)
    {
      Allure::Gpx::PointSerializer::KEY_TIME => time,
      Allure::Gpx::PointSerializer::KEY_DISTANCE => distance,
      Allure::Gpx::PointSerializer::KEY_ELEVATION => elevation,
      Allure::Gpx::PointSerializer::KEY_SPEED => speed,
      Allure::Gpx::PointSerializer::KEY_HEART_RATE => heart_rate,
      Allure::Gpx::PointSerializer::KEY_CADENCE => cadence,
      Allure::Gpx::PointSerializer::KEY_POWER => power
    }.compact
  end
end
