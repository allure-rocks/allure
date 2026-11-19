# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/demo/emails")

RSpec.describe DemoSeed::Emails do
  it "derives the domain from the instance host" do
    with_env("DEMO_EMAIL_DOMAIN" => nil, "FEDERATION_BASE_URL" => "http://allure.test:3001",
             "FEDERATION_PROTOCOL" => nil) do
      expect(described_class.domain).to eq("allure.test")
      expect(described_class.for("marie")).to eq("marie@allure.test")
    end
  end

  it "follows the demo host without any setting" do
    with_env("DEMO_EMAIL_DOMAIN" => nil, "FEDERATION_BASE_URL" => "https://demo.allure.rocks",
             "FEDERATION_PROTOCOL" => nil) do
      expect(described_class.for("marie")).to eq("marie@demo.allure.rocks")
    end
  end

  it "pins another domain, normalizing case and a leading @" do
    with_env("DEMO_EMAIL_DOMAIN" => " @Example.Test ", "FEDERATION_BASE_URL" => "http://allure.test:3001",
             "FEDERATION_PROTOCOL" => nil) do
      expect(described_class.domain).to eq("example.test")
    end
  end

  it "ignores a blank override" do
    with_env("DEMO_EMAIL_DOMAIN" => "  ", "FEDERATION_BASE_URL" => "http://allure.test:3001",
             "FEDERATION_PROTOCOL" => nil) do
      expect(described_class.domain).to eq("allure.test")
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
