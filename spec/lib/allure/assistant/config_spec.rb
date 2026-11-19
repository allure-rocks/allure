# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Assistant::Config do
  it "is disabled until both the endpoint and the model are set" do
    with_env("AI_BASE_URL" => nil, "AI_MODEL" => nil) do
      expect(described_class).not_to be_enabled
    end

    with_env("AI_BASE_URL" => "http://litellm.test:4000", "AI_MODEL" => nil) do
      expect(described_class).not_to be_enabled
    end

    with_env("AI_BASE_URL" => nil, "AI_MODEL" => "qwen") do
      expect(described_class).not_to be_enabled
    end

    with_env("AI_BASE_URL" => "http://litellm.test:4000", "AI_MODEL" => "qwen") do
      expect(described_class).to be_enabled
    end
  end

  it "reads the endpoint, the model and the key, ignoring blanks" do
    with_env("AI_BASE_URL" => " http://litellm.test:4000 ", "AI_MODEL" => "qwen", "AI_API_KEY" => " ") do
      expect(described_class.base_url).to eq("http://litellm.test:4000")
      expect(described_class.model).to eq("qwen")
      expect(described_class.api_key).to be_nil
    end

    with_env("AI_BASE_URL" => "http://litellm.test:4000", "AI_MODEL" => "qwen", "AI_API_KEY" => "sk-virtual") do
      expect(described_class.api_key).to eq("sk-virtual")
    end
  end

  it "falls back to the documented defaults" do
    with_env("AI_TIMEOUT" => nil, "AI_MAX_REQUESTS_PER_DAY" => nil) do
      expect(described_class.timeout).to eq(300)
      expect(described_class.max_requests_per_day).to eq(500)
    end
  end

  it "ignores invalid tuning values" do
    with_env("AI_TIMEOUT" => "long", "AI_MAX_REQUESTS_PER_DAY" => "0") do
      expect(described_class.timeout).to eq(300)
      expect(described_class.max_requests_per_day).to eq(500)
    end
  end

  it "parses AI_REQUEST_OPTIONS as a JSON object" do
    with_env("AI_REQUEST_OPTIONS" => '{"reasoning_effort":"none"}') do
      expect(described_class.request_options).to eq("reasoning_effort" => "none")
    end
  end

  it "ignores a malformed or non-object AI_REQUEST_OPTIONS" do
    with_env("AI_REQUEST_OPTIONS" => "{reasoning_effort") do
      expect(described_class.request_options).to eq({})
    end

    with_env("AI_REQUEST_OPTIONS" => '["reasoning_effort"]') do
      expect(described_class.request_options).to eq({})
    end

    with_env("AI_REQUEST_OPTIONS" => nil) do
      expect(described_class.request_options).to eq({})
    end
  end

  it "builds the client for the configured endpoint" do
    with_env(
      "AI_BASE_URL" => "http://litellm.test:4000",
      "AI_MODEL" => "qwen",
      "AI_API_KEY" => "sk-virtual",
      "AI_TIMEOUT" => "120",
      "AI_REQUEST_OPTIONS" => '{"reasoning_effort":"none"}'
    ) do
      expect(described_class.client).to have_attributes(
        base_url: "http://litellm.test:4000", model: "qwen", timeout: 120
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
