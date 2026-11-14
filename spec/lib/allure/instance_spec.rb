# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Instance do
  def with_env(vars)
    previous = vars.transform_values { |_| nil }
    vars.each_key { |k| previous[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  it "defaults the name and hides the host when nothing is configured" do
    with_env(
      "INSTANCE_NAME" => nil, "INSTANCE_DESCRIPTION" => nil,
      "INSTANCE_HOST_NAME" => nil, "INSTANCE_HOST_URL" => nil
    ) do
      expect(described_class.name).to eq("Allure")
      expect(described_class.description).to be_nil
      expect(described_class.host_name).to be_nil
      expect(described_class.host_url).to be_nil
      expect(described_class).not_to be_hosted_by
    end
  end

  it "reads configured values, stripped" do
    with_env(
      "INSTANCE_NAME" => "  Mon serveur  ", "INSTANCE_DESCRIPTION" => "  Une description. ",
      "INSTANCE_HOST_NAME" => " Camille ", "INSTANCE_HOST_URL" => "https://example.org/about"
    ) do
      expect(described_class.name).to eq("Mon serveur")
      expect(described_class.description).to eq("Une description.")
      expect(described_class.host_name).to eq("Camille")
      expect(described_class.host_url).to eq("https://example.org/about")
      expect(described_class).to be_hosted_by
    end
  end

  it "ignores a host URL that is not an absolute http(s) URI" do
    [ "javascript:alert(1)", "not a url", "ftp://example.org", "/relative", "https://example.org?q=1" ].each do |value|
      with_env("INSTANCE_HOST_URL" => value) do
        expect(described_class.host_url).to be_nil
      end
    end
  end

  it "reads the environment at call time" do
    with_env("INSTANCE_NAME" => nil) do
      expect(described_class.name).to eq("Allure")
    end

    with_env("INSTANCE_NAME" => "Plus tard") do
      expect(described_class.name).to eq("Plus tard")
    end
  end

  it "offers the upstream source when the operator configured none" do
    with_env("ALLURE_SOURCE_URL" => nil) do
      expect(described_class.source_url).to eq("https://github.com/allure-rocks/allure")
    end
  end

  describe ".reserved_usernames" do
    it "keeps the configured name in username space" do
      with_env("INSTANCE_NAME" => "Mon Club") do
        expect(described_class.reserved_usernames).to eq(%w[mon_club])
      end

      with_env("INSTANCE_NAME" => "allure.rocks") do
        expect(described_class.reserved_usernames).to eq(%w[allure_rocks])
      end

      with_env("INSTANCE_NAME" => nil) do
        expect(described_class.reserved_usernames).to eq(%w[allure])
      end
    end

    it "transliterates, collapses runs, trims the ends and caps the length" do
      with_env("INSTANCE_NAME" => "  L'Allure — Édition !  ") do
        expect(described_class.reserved_usernames).to eq(%w[l_allure_edition])
      end

      with_env("INSTANCE_NAME" => "a" * 31) do
        expect(described_class.reserved_usernames).to eq([ "a" * 30 ])
      end
    end

    it "reserves nothing when the name carries no username" do
      with_env("INSTANCE_NAME" => "★★★") do
        expect(described_class.reserved_usernames).to eq([])
      end
    end
  end
end
