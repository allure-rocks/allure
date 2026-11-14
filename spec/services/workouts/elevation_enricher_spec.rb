# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ElevationEnricher do
  let(:user) { create(:user) }
  let(:client) { instance_double(Allure::Elevation::OpenTopoData) }
  let(:sleeps) { [] }
  let(:sleeper) { ->(seconds) { sleeps << seconds } }
  let(:config_class) do
    Data.define(:base_url, :dataset, :sample_metres, :requests_per_second, :max_requests_per_workout) do
      def configured? = true
    end
  end
  let(:default_config) do
    {
      base_url: "https://elevation.test",
      dataset: "mapzen",
      sample_metres: 50.0,
      requests_per_second: 2.0,
      max_requests_per_workout: 10
    }
  end
  let(:config) { config_class.new(**default_config) }

  before do
    allow(client).to receive(:elevations) { |locations| Array.new(locations.length) { 100.0 } }
  end

  def config_with(**overrides)
    config_class.new(**default_config.merge(overrides))
  end

  def elevation_less_workout(points: 3)
    workout = create(:workout, user:, sport: catalog_sport("running"), import_format: "gpx")
    workout.original_file.attach(
      io: StringIO.new(gpx_with_points(points)),
      filename: "terrain.gpx",
      content_type: "application/gpx+xml"
    )
    workout
  end

  def gpx_with_points(count)
    points = Array.new(count) do |index|
      time = Time.at(1_700_000_000 + index).utc.iso8601
      %(<trkpt lat="45.0" lon="#{format("%.6f", 6.0 + (index * 0.001))}"><time>#{time}</time></trkpt>)
    end.join
    <<~GPX
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx version="1.1" creator="RSpec" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><trkseg>#{points}</trkseg></trk>
      </gpx>
    GPX
  end

  def enrich(workout, config: self.config)
    described_class.new(workout:, client:, config:, sleeper:).call
  end

  it "stores the fetched profile and reports it ready" do
    workout = elevation_less_workout

    result = enrich(workout)

    expect(result.status).to eq("ready")
    expect(result.samples_count).to eq(3)
    expect(result.requests_count).to eq(1)
    expect(workout.reload.elevation).to have_attributes(
      status: "ready",
      provider: "https://elevation.test",
      dataset: "mapzen",
      algorithm_version: WorkoutElevation::ALGORITHM_VERSION,
      requests_count: 1,
      last_error: nil
    )
    expect(workout.elevation.samples).to all(include("elevation" => 100.0))
  end

  it "reports partial when the provider covers only part of the route" do
    allow(client).to receive(:elevations) do |locations|
      locations.each_with_index.map { |_location, index| index.zero? ? 100.0 : nil }
    end
    workout = elevation_less_workout

    result = enrich(workout)

    expect(result.status).to eq("partial")
    expect(workout.reload.elevation.samples.map { |sample| sample["elevation"] }).to eq([ 100.0, nil, nil ])
  end

  it "reports unavailable when the provider covers nothing" do
    allow(client).to receive(:elevations) { |locations| Array.new(locations.length) }

    result = enrich(elevation_less_workout)

    expect(result.status).to eq("unavailable")
  end

  it "records a failed fetch and re-raises" do
    allow(client).to receive(:elevations).and_raise(Allure::Elevation::OpenTopoData::UnavailableError, "HTTP 500")
    workout = elevation_less_workout

    expect { enrich(workout) }.to raise_error(Allure::Elevation::OpenTopoData::UnavailableError)

    expect(workout.reload.elevation).to have_attributes(status: "failed")
    expect(workout.elevation.last_error).to match(/HTTP 500/)
  end

  it "reuses a current cached profile without another request" do
    workout = elevation_less_workout
    enrich(workout)

    expect(client).not_to receive(:elevations)

    expect(enrich(workout).status).to eq("ready")
  end

  it "refetches when the cached profile came from another provider" do
    workout = elevation_less_workout
    enrich(workout)
    workout.elevation.update!(provider: "https://old.test")

    expect(client).to receive(:elevations).once { |locations| Array.new(locations.length) { 100.0 } }

    enrich(workout)

    expect(workout.reload.elevation.provider).to eq("https://elevation.test")
  end

  it "throttles between provider requests" do
    workout = elevation_less_workout(points: 250)

    result = enrich(workout)

    expect(client).to have_received(:elevations).exactly(3).times
    expect(sleeps).to eq([ 0.5, 0.5 ])
    expect(result.requests_count).to eq(3)
  end

  it "coarsens the sampling to respect the request budget" do
    workout = elevation_less_workout(points: 250)

    result = enrich(workout, config: config_with(max_requests_per_workout: 1))

    expect(client).to have_received(:elevations).once
    expect(result.requests_count).to eq(1)
  end

  it "refuses to fetch without a configured provider" do
    workout = elevation_less_workout
    config = double("config", configured?: false)

    expect { enrich(workout, config:) }
      .to raise_error(Workouts::ElevationEnricher::ProviderNotConfiguredError)
    expect(workout.reload.elevation).to be_nil
  end
end
