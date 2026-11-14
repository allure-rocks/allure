# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Weather::Markers do
  def row(time, temperature: 12.0, code: 3, wind: 4.0, direction: 200.0)
    Allure::Weather::Series::Row.new(
      time:, temperature:, apparent_temperature: temperature, humidity: 70, precipitation: 0.0, weather_code: code,
      cloud_cover: 80, pressure: 1010.0, wind_speed: wind, wind_direction: direction, wind_gusts: wind * 2
    )
  end

  let(:distances) { [ 0.0, 10_000.0, 20_000.0, 30_000.0, 40_000.0 ] }

  def markers(rows, distances: self.distances, total: 40_000.0)
    described_class.new(rows:, distances:, total_distance: total).call
  end

  it "marks the start, then each change of condition, wind sector or 2 °C" do
    rows = [
      row(0), row(3_600), row(7_200, code: 61), row(10_800, code: 61, direction: 300.0),
      row(14_400, code: 61, direction: 300.0, temperature: 14.5)
    ]

    expect(markers(rows).map(&:distance)).to eq([ 0.0, 20_000.0, 30_000.0, 40_000.0 ])
  end

  it "keeps markers apart, ignores a calm wind and caps their number" do
    close = [ row(0), row(60, code: 61) ]
    expect(markers(close, distances: [ 0.0, 1_000.0 ]).map(&:distance)).to eq([ 20_000.0 ])

    calm = [ row(0, wind: 0.5), row(3_600, wind: 0.8, direction: 20.0) ]
    expect(markers(calm, distances: [ 0.0, 20_000.0 ]).length).to eq(1)

    many = Array.new(12) { |index| row(index * 3_600, temperature: index * 3.0) }
    expect(markers(many, distances: Array.new(12) { |index| index * 10_000.0 }, total: 110_000.0).length).to eq(6)
  end

  it "puts a single marker halfway when the weather never changes" do
    result = markers([ row(0), row(3_600), row(7_200) ], distances: [ 0.0, 20_000.0, 40_000.0 ])

    expect(result.map(&:distance)).to eq([ 20_000.0 ])
  end

  it "maps each row's instant to the distance covered" do
    start = Time.utc(2026, 5, 10, 8)
    points = [ 0, 600, 1_200 ].map do |offset|
      Allure::Segments::Point.new(index: 0, segment_index: 0, segment_point_index: 0, time: start + offset,
                                  elapsed_time: offset, distance: offset * 5.0, longitude: 6.0, latitude: 45.0,
                                  elevation: nil, speed: nil, heart_rate: nil, cadence: nil, power: nil)
    end
    rows = [ row(start.to_i), row(start.to_i + 900) ]

    expect(described_class.distances(points, rows)).to eq([ 0.0, 4_500.0 ])
  end
end
