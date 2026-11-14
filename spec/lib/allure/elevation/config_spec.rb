# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Elevation::Config do
  it "is disabled without a base URL" do
    with_env("ELEVATION_BASE_URL" => nil) do
      expect(described_class).not_to be_configured
      expect(described_class.base_url).to be_nil
    end
  end

  it "reads the configured provider and dataset" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test/", "ELEVATION_DATASET" => "srtm30m") do
      expect(described_class).to be_configured
      expect(described_class.base_url).to eq("https://elevation.test/")
      expect(described_class.dataset).to eq("srtm30m")
    end
  end

  it "falls back to the documented defaults" do
    with_env(
      "ELEVATION_BASE_URL" => "https://elevation.test",
      "ELEVATION_DATASET" => nil,
      "ELEVATION_INTERPOLATION" => nil,
      "ELEVATION_SAMPLE_METRES" => nil,
      "ELEVATION_REQUESTS_PER_SECOND" => nil,
      "ELEVATION_MAX_REQUESTS_PER_WORKOUT" => nil
    ) do
      expect(described_class.dataset).to eq("mapzen")
      expect(described_class.interpolation).to eq("bilinear")
      expect(described_class.sample_metres).to eq(50.0)
      expect(described_class.requests_per_second).to eq(5.0)
      expect(described_class.max_requests_per_workout).to eq(40)
    end
  end

  it "ignores invalid tuning values" do
    with_env(
      "ELEVATION_BASE_URL" => "https://elevation.test",
      "ELEVATION_SAMPLE_METRES" => "-1",
      "ELEVATION_REQUESTS_PER_SECOND" => "fast",
      "ELEVATION_MAX_REQUESTS_PER_WORKOUT" => "0"
    ) do
      expect(described_class.sample_metres).to eq(50.0)
      expect(described_class.requests_per_second).to eq(5.0)
      expect(described_class.max_requests_per_workout).to eq(40)
    end
  end

  it "builds a client for the configured provider" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test", "ELEVATION_DATASET" => "srtm30m") do
      expect(described_class.client).to have_attributes(
        base_url: "https://elevation.test", dataset: "srtm30m", interpolation: "bilinear"
      )
    end
  end

  def with_env(values)
    previous = values.to_h { |key, _value| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
