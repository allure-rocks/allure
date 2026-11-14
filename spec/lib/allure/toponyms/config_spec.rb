# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Toponyms::Config do
  it "is disabled without a base URL" do
    with_env("GEOCODING_BASE_URL" => nil) do
      expect(described_class).not_to be_configured
      expect(described_class.base_url).to be_nil
    end
  end

  it "reads the configured provider" do
    with_env("GEOCODING_BASE_URL" => "https://geocoding.test") do
      expect(described_class).to be_configured
      expect(described_class.base_url).to eq("https://geocoding.test")
    end
  end

  it "falls back to a single serialized job at ten requests per second" do
    with_env("GEOCODING_REQUESTS_PER_SECOND" => nil, "GEOCODING_CONCURRENCY" => nil) do
      expect(described_class.requests_per_second).to eq(10.0)
      expect(described_class.concurrency).to eq(1)
      expect(described_class.request_interval).to eq(0.1)
    end
  end

  it "splits the instance request budget across concurrent jobs" do
    with_env("GEOCODING_REQUESTS_PER_SECOND" => "30", "GEOCODING_CONCURRENCY" => "3") do
      expect(described_class.requests_per_second).to eq(30.0)
      expect(described_class.concurrency).to eq(3)
      expect(described_class.request_interval).to eq(0.1)
    end
  end

  it "ignores invalid tuning values" do
    with_env("GEOCODING_REQUESTS_PER_SECOND" => "fast", "GEOCODING_CONCURRENCY" => "0") do
      expect(described_class.requests_per_second).to eq(10.0)
      expect(described_class.concurrency).to eq(1)
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
