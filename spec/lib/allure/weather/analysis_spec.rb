# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Allure::Weather analysis" do
  let(:start) { Time.utc(2026, 5, 10, 8, 20) }

  # A straight line north (or back south) at ~5 m/s, one point every 20 s.
  def track(minutes:, from: [ 45.0, 6.0 ], northward: true, segment_index: 0, started: start, distance_offset: 0.0)
    step = 100.0 / 111_195.0
    (0..(minutes * 3)).map do |index|
      latitude = from[0] + (northward ? 1 : -1) * index * step
      Allure::Segments::Point.new(
        index:, segment_index:, segment_point_index: index, time: started + index * 20,
        elapsed_time: index * 20.0, distance: distance_offset + index * 100.0,
        longitude: from[1], latitude:, elevation: 210.0 + index, speed: 5.0,
        heart_rate: nil, cadence: nil, power: nil
      )
    end
  end

  def row(time, wind:, direction:, temperature: 12.0, code: 2, precipitation: 0.0, day: true)
    Allure::Weather::Series::Row.new(
      time: time.to_i, temperature:, apparent_temperature: temperature - 2, humidity: 70, precipitation:,
      weather_code: code, cloud_cover: 50, pressure: 1013.0, wind_speed: wind, wind_direction: direction,
      wind_gusts: wind * 2, day:
    )
  end

  describe Allure::Weather::Sampler do
    it "samples the start, each whole hour and the finish on a 0.1° grid" do
      points = track(minutes: 150)
      plan = described_class.call(points)

      times = plan.samples.map(&:time)
      expect(times.first).to eq(start.to_i)
      expect(times[1..-2]).to eq([ Time.utc(2026, 5, 10, 9).to_i, Time.utc(2026, 5, 10, 10).to_i ])
      expect(times.last).to eq(points.last.time.to_i)
      expect(plan.cells.map(&:latitude)).to all(satisfy { |value| (value * 10).round(6) == (value * 10).round })
      expect(plan.cells.first.latitude).to eq(45.0)
      expect(plan.cells.first.elevation % 10).to eq(0)
    end

    it "deduplicates cells and keeps the plan stable" do
      plan = described_class.call(track(minutes: 10))

      expect(plan.cells.length).to eq(1)
      expect(plan.samples.map(&:cell)).to all(eq(0))
      expect(described_class.call(track(minutes: 10)).to_json_samples).to eq(plan.to_json_samples)
    end

    it "is empty for an untimed or positionless track" do
      frozen = track(minutes: 5).map { |point| point.with(time: start) }
      positionless = track(minutes: 5).map { |point| point.with(latitude: nil, longitude: nil) }

      expect(described_class.call(frozen)).to be_empty
      expect(described_class.call(positionless)).to be_empty
    end
  end

  describe Allure::Weather::Series do
    let(:hours) { [ Time.utc(2026, 5, 10, 8), Time.utc(2026, 5, 10, 9) ].map(&:to_i) }
    let(:response) do
      {
        "time" => hours,
        "temperature_2m" => [ 10.0, 14.0 ], "apparent_temperature" => [ 8.0, 12.0 ],
        "relative_humidity_2m" => [ 80.0, 60.0 ], "precipitation" => [ 0.0, 1.2 ], "weather_code" => [ 3.0, 61.0 ],
        "cloud_cover" => [ 100.0, 80.0 ], "surface_pressure" => [ 1010.0, 1012.0 ],
        "wind_speed_10m" => [ 4.0, 4.0 ], "wind_direction_10m" => [ 350.0, 10.0 ], "wind_gusts_10m" => [ 8.0, 9.0 ]
      }
    end

    it "interpolates between the bounding hours, wind through its components" do
      sample = Allure::Weather::Sampler::Sample.new(time: hours.first + 1_800, cell: 0)
      row = described_class.call(responses: [ response ], samples: [ sample ]).first

      expect(row.temperature).to eq(12.0)
      expect(row.wind_speed).to eq(4.0)
      expect([ row.wind_direction, 360 - row.wind_direction ].min).to be < 1
      expect(row.precipitation).to eq(1.2)
      expect(row.weather_code).to eq(61)
      expect(row.to_h.keys).to eq(%w[t temp feels rh precip code cloud pres wind dir gust day])
      expect(Allure::Weather::Series::Row.from_h(row.to_h)).to eq(row)
    end

    it "marks a series without values as incomplete" do
      empty = response.transform_values { |values| values.map { nil } }.merge("time" => hours)
      rows = described_class.call(responses: [ empty ], samples: [ Allure::Weather::Sampler::Sample.new(time: hours.first, cell: 0) ])

      expect(described_class.complete?(rows)).to be(false)
    end
  end

  describe Allure::Weather::WindExposure do
    it "splits an out-and-back under a constant wind between head and tail" do
      out = track(minutes: 30)
      back = track(minutes: 30, from: [ out.last.latitude, 6.0 ], northward: false, segment_index: 1,
                   started: out.last.time + 60, distance_offset: out.last.distance)
      rows = [ row(start - 3_600, wind: 5.0, direction: 0.0), row(start + 7_200, wind: 5.0, direction: 0.0) ]

      result, = described_class.new(points: out + back, rows:).call

      expect(result.head).to be_within(0.02).of(0.5)
      expect(result.tail).to be_within(0.02).of(0.5)
      expect(result.cross).to be_within(0.01).of(0.0)
      expect(result.headwind).to be_within(0.1).of(0.0)
    end

    it "counts a wind from the side as crosswind and reports the head component" do
      rows = [ row(start, wind: 6.0, direction: 90.0), row(start + 3_600, wind: 6.0, direction: 30.0) ]

      result, = described_class.new(points: track(minutes: 30), rows:).call

      expect(result.cross + result.head).to be_within(1e-6).of(1.0)
      expect(result.headwind).to be > 0
    end

    it "ignores stopped stretches and reports per range" do
      points = track(minutes: 20)
      ranges = [ [ 0.0, 3_000.0 ], [ 3_000.0, 6_000.0 ] ]
      rows = [ row(start, wind: 3.0, direction: 180.0), row(start + 3_600, wind: 3.0, direction: 180.0) ]

      result, per_range = described_class.new(points:, rows:, stopped_speed_threshold_mps: 10.0, ranges:).call
      expect(result).not_to be_present

      result, per_range = described_class.new(points:, rows:, ranges:).call
      expect(result.tail).to eq(1.0)
      expect(per_range.map(&:tail)).to eq([ 1.0, 1.0 ])
      expect(result.headwind).to be_within(0.01).of(-3.0)
    end
  end

  describe Allure::Weather::Conditions do
    it "maps WMO codes and favours a lasting precipitation" do
      expect(described_class.token(61)).to eq("rain")
      expect(described_class.token(1234)).to be_nil
      expect(described_class.dominant(%w[overcast overcast overcast rain])).to eq("rain")
      expect(described_class.dominant(%w[overcast overcast overcast overcast overcast rain])).to eq("overcast")
    end
  end

  describe Allure::Weather::Icons do
    it "names the Meteocons icon of every condition, day and night" do
      expect(described_class.name("thunderstorm")).to eq("thunderstorms-rain")
      expect(described_class.name("clear")).to eq("clear-day")
      expect(described_class.name("clear", day: false)).to eq("clear-night")
      expect(described_class.name("showers", day: false)).to eq("partly-cloudy-night-rain")
      expect(described_class.name("drizzle", day: false)).to eq("drizzle")
      expect(described_class.name(nil)).to eq("not-available")
      expect(described_class.name("nonsense")).to eq("not-available")
    end

    it "ships every named icon, and reads the fallback for an unknown one" do
      root = WeatherHelper::WEATHER_ICON_ROOT
      Allure::Weather::Conditions::TOKENS.each do |token|
        [ true, false ].each do |day|
          file = root.join("#{described_class.name(token, day:)}.svg")
          expect(file).to exist, "missing #{file}"
        end
      end
      expect(described_class.markup("nonsense", root:)).to eq(described_class.markup("not-available", root:))
    end
  end

  describe Allure::Weather::Summary do
    it "summarises the series with an hourly precipitation total" do
      rows = [
        row(start, wind: 4.0, direction: 270.0, temperature: 10.0, code: 3, precipitation: 0.5),
        row(start + 600, wind: 6.0, direction: 270.0, temperature: 14.0, code: 61, precipitation: 0.5),
        row(start + 4_000, wind: 5.0, direction: 270.0, temperature: 12.0, code: 61, precipitation: 1.0)
      ]
      exposure = Allure::Weather::WindExposure::Result.new(distance: 1_000.0, head: 0.2, tail: 0.3, cross: 0.5, headwind: -0.4)

      summary = described_class.call(rows, exposure)

      expect(summary).to include(
        "condition" => "rain", "temperature_min" => 10.0, "temperature_max" => 14.0, "precipitation" => 1.5,
        "wind_speed" => 5.0, "wind_gusts" => 12.0, "wind_direction" => 270
      )
      expect(summary["wind_exposure"]).to eq("head" => 0.2, "tail" => 0.3, "cross" => 0.5, "headwind" => -0.4)
      expect(summary["is_day"]).to be(true)
    end

    it "takes the icon's day or night variant from the majority of rows" do
      afternoon = [ row(start, wind: 4.0, direction: 270.0), row(start + 3_600, wind: 4.0, direction: 270.0) ]
      night = afternoon.map { |entry| entry.with(day: false) }

      expect(described_class.call(afternoon, nil)["is_day"]).to be(true)
      expect(described_class.call([ afternoon.first, night.last ], nil)["is_day"]).to be(true)
      expect(described_class.call(night, nil)["is_day"]).to be(false)

      unknown = afternoon.map { |entry| entry.with(day: nil) }
      expect(described_class.call(unknown, nil)).not_to have_key("is_day")
    end
  end
end
