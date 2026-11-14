# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gitlab::Config do
  describe "defaults" do
    it "is disabled by default" do
      config = described_class.new(
        enabled: false,
        project_id: "group/allure",
        token: "secret"
      )

      expect(config).not_to be_enabled
      expect(config).not_to be_configured
    end

    it "normalizes labels from a comma-separated value" do
      config = described_class.new(labels: "feedback, allure, feedback")

      expect(config.labels).to eq(%w[feedback allure])
    end
  end

  describe "configuration" do
    subject(:config) do
      described_class.new(
        enabled: true,
        api_url: "https://gitlab.example/api/v4/",
        project_id: "group/allure",
        token: "secret-token",
        labels: [ "feedback" ],
        confidential: true
      )
    end

    it "is configured when all required values are present" do
      expect(config).to be_configured
      expect(config).to be_confidential
      expect(config).to be_secure
    end

    it "requires a project when enabled" do
      invalid = described_class.new(enabled: true, token: "secret", project_id: "")

      expect { invalid.validate! }.to raise_error(described_class::InvalidConfiguration, /PROJECT_ID/)
    end

    it "requires a token when enabled" do
      invalid = described_class.new(enabled: true, project_id: "group/allure", token: "")

      expect { invalid.validate! }.to raise_error(described_class::InvalidConfiguration, /TOKEN/)
    end

    it "rejects URLs with credentials or query parameters" do
      [
        "https://user:password@gitlab.example/api/v4",
        "https://gitlab.example/api/v4?token=secret",
        "not-a-url"
      ].each do |api_url|
        invalid = described_class.new(enabled: true, api_url:, project_id: "group/allure", token: "secret")

        expect { invalid.validate! }.to raise_error(described_class::InvalidConfiguration)
      end
    end

    it "reads values from the environment" do
      config = with_env(
        "GITLAB_ENABLED" => "true",
        "GITLAB_API_URL" => "https://gitlab.example/api/v4",
        "GITLAB_PROJECT_ID" => "group/allure",
        "GITLAB_TOKEN" => "secret-token"
      ) { described_class.new }

      expect(config).to be_configured
      expect(config.project_id).to eq("group/allure")
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
