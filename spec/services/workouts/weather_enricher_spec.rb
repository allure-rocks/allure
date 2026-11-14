# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::WeatherEnricher, :weather do
  let(:user) { create(:user, weather_enrichment_enabled: true) }
  let(:workout) { weather_workout(user:) }

  it "fetches the hourly series along the route and stores its analysis" do
    stub = stub_open_meteo(wind: 5.0, direction: 0.0)

    record = described_class.new(workout:).call

    expect(stub).to have_been_requested.once
    expect(record).to be_ready
    expect(record.endpoint).to eq("forecast")
    expect(record.requests_count).to eq(1)
    expect(record.series.length).to eq(record.samples.length)
    expect(record.samples).to all(include("lat", "lon", "t", "cell"))
    expect(record.exposure["head"]).to eq(1.0)
    expect(record.summary).to include("temperature_min" => 12.0, "condition" => "partly_cloudy", "wind_direction" => 0)
    expect(workout.reload.weather_start["temp"]).to eq(12.0)
    expect(workout.weather_end["t"]).to eq((workout.started_at + 90.minutes).to_i)
  end

  it "never sends a coordinate finer than one decimal" do
    stub_open_meteo
    described_class.new(workout:).call

    expect(a_request(:get, /forecast\.weather\.test/).with { |request|
      query = Rack::Utils.parse_query(URI(request.uri).query)
      (query["latitude"].split(",") + query["longitude"].split(",")).all? { |value| value.match?(/\A-?\d+\.\d\z/) }
    }).to have_been_made
  end

  it "converges offline when the plan did not change" do
    stub = stub_open_meteo
    described_class.new(workout:).call
    workout.weather.update_columns(analysis_version: 0, summary: {})

    record = described_class.new(workout: workout.reload).call

    expect(stub).to have_been_requested.once
    expect(record.analysis_version).to eq(described_class::ANALYSIS_VERSION)
    expect(record.summary).to be_present
  end

  it "falls back to the archive when the forecast endpoint has no values" do
    stub_open_meteo(temperature: nil, wind: nil)
    archive = stub_open_meteo(endpoint: :archive)

    record = described_class.new(workout:).call

    expect(archive).to have_been_requested
    expect(record.endpoint).to eq("archive")
  end

  it "asks the archive first for an old workout" do
    archive = stub_open_meteo(endpoint: :archive)
    old = weather_workout(user:, started_at: Time.utc(2015, 7, 1, 9))

    expect(described_class.new(workout: old).call.endpoint).to eq("archive")
    expect(archive).to have_been_requested
  end

  it "records an untimed track as unavailable" do
    workout.track_segments.first.update!(points: workout.track_segments.first.points.map { |point| point.merge("t" => 0) })

    record = described_class.new(workout: workout.reload).call

    expect(record).to be_unavailable
    expect(record.unavailable_reason).to eq("untimed")
  end

  it "refuses to exceed the daily budget" do
    other = weather_workout(user:)
    create(:workout_weather, workout: other, status: "ready", requests_count: 5_000, fetched_at: 1.hour.ago)

    expect { described_class.new(workout:).call }.to raise_error(described_class::BudgetExhaustedError)
  end

  it "keeps a retryable failure pending and marks a rejected request failed" do
    stub_open_meteo(status: 503)
    Workouts::WeatherRefresh.new(workout:).call
    expect { described_class.new(workout: workout.reload).call }.to raise_error(Allure::Weather::OpenMeteo::UnavailableError)
    expect(workout.weather.reload).to be_pending
    expect(workout.weather.last_error).to be_present

    stub_open_meteo(status: 400)
    expect(described_class.new(workout: workout.reload).call).to be_failed
  end

  it "asks nothing for an account that did not consent" do
    user.update!(weather_enrichment_enabled: false)

    expect(described_class.new(workout: workout.reload).call).to be_nil
    expect(a_request(:get, /weather\.test/)).not_to have_been_made
  end

  it "discards the weather of a workout turned virtual" do
    stub_open_meteo
    described_class.new(workout:).call
    workout.update!(sport: catalog_sport("cycling_virtual"))

    described_class.new(workout: workout.reload).call

    expect(workout.reload.weather).to be_nil
    expect(workout.weather_start).to be_nil
  end
end
