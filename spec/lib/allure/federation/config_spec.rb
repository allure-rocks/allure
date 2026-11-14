# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Federation::Config do
  subject(:config) { described_class.new(base_url: "https://allure.example", protocol: "https") }

  describe "identity derivation" do
    it "builds Mastodon-style actor URIs" do
      expect(config.actor_uri("marie")).to eq("https://allure.example/users/marie")
    end

    it "uses a #main-key fragment for the key id, as every major implementation expects" do
      expect(config.key_id("marie")).to eq("https://allure.example/users/marie#main-key")
    end

    it "derives the collection endpoints from the actor URI" do
      expect(config.inbox_uri("marie")).to eq("https://allure.example/users/marie/inbox")
      expect(config.outbox_uri("marie")).to eq("https://allure.example/users/marie/outbox")
      expect(config.followers_uri("marie")).to eq("https://allure.example/users/marie/followers")
      expect(config.following_uri("marie")).to eq("https://allure.example/users/marie/following")
    end

    it "points the human-facing profile at /@handle" do
      expect(config.profile_url("marie")).to eq("https://allure.example/@marie")
    end

    it "derives protocol discovery and shared inbox URIs" do
      expect(config.shared_inbox_uri).to eq("https://allure.example/inbox")
      expect(config.webfinger_uri).to eq("https://allure.example/.well-known/webfinger")
      expect(config.nodeinfo_uri("2.2")).to eq("https://allure.example/nodeinfo/2.2")
    end

    it "derives workout publication objects from the Wanderer trail path" do
      expect(config.workout_publication_uri("2222222222222222222222"))
        .to eq("https://allure.example/api/v1/trail/2222222222222222222222")
    end

    it "derives segment publication objects from the dedicated segment path" do
      expect(config.segment_publication_uri("2222222222222222222222"))
        .to eq("https://allure.example/api/v1/segment/2222222222222222222222")
    end

    it "builds the WebFinger subject" do
      expect(config.handle("marie")).to eq("marie@allure.example")
      expect(config.acct("marie")).to eq("acct:marie@allure.example")
    end
  end

  describe "#domain" do
    it "omits the port when it is the scheme default" do
      expect(described_class.new(base_url: "https://allure.example:443").domain)
        .to eq("allure.example")
    end

    it "keeps a non-default port, because that is how remote servers address us" do
      expect(described_class.new(base_url: "http://allure-a.test:3000").domain)
        .to eq("allure-a.test:3000")
    end
  end

  describe "#local_uri?" do
    subject(:config) { described_class.new(base_url: "http://allure-a.test:3000", protocol: "http") }

    it "accepts an exact match" do
      expect(config).to be_local_uri("http://allure-a.test:3000/users/marie")
    end

    # The whole point of checking the port: in the Tier-2 ring several instances
    # share a host and differ only by port. Ignoring it would let one instance
    # claim another's actors.
    it "rejects a URI differing only by port" do
      expect(config).not_to be_local_uri("http://allure-a.test:3001/users/marie")
    end

    it "rejects a URI differing only by scheme" do
      expect(config).not_to be_local_uri("https://allure-a.test:3000/users/marie")
    end

    it "rejects a different host" do
      expect(config).not_to be_local_uri("http://allure-b.test:3000/users/marie")
    end

    it "rejects garbage rather than raising" do
      expect(config).not_to be_local_uri("not a uri")
    end

    it "rejects credentials, queries, and fragments" do
      expect(config).not_to be_local_uri("http://allure-a.test:3000/users/marie?format=json")
      expect(config).not_to be_local_uri("http://allure-a.test:3000/users/marie#key")
      expect(config).not_to be_local_uri("http://user:secret@allure-a.test:3000/users/marie")
    end
  end

  describe "validation" do
    it "rejects a relative base URL" do
      expect { described_class.new(base_url: "/allure") }
        .to raise_error(described_class::InvalidBaseUrl, /absolute/)
    end

    it "rejects a non-HTTP scheme" do
      expect { described_class.new(base_url: "ftp://allure.example") }
        .to raise_error(described_class::InvalidBaseUrl, /http or https/)
    end

    # Actor URIs are built by concatenation. A base URL carrying a path would
    # silently produce URIs that no longer round-trip through WebFinger.
    it "rejects a base URL with a path" do
      expect { described_class.new(base_url: "https://allure.example/federation") }
        .to raise_error(described_class::InvalidBaseUrl, /path/)
    end

    it "rejects credentials, queries, and fragments" do
      [
        "https://user:secret@allure.example",
        "https://allure.example?tenant=one",
        "https://allure.example/#actor"
      ].each do |base_url|
        expect { described_class.new(base_url:) }
          .to raise_error(described_class::InvalidBaseUrl)
      end
    end

    it "rejects an invalid protocol" do
      expect { described_class.new(base_url: "https://allure.example", protocol: "ftp") }
        .to raise_error(described_class::InvalidBaseUrl, /FEDERATION_PROTOCOL/)
    end

    it "rejects a protocol that differs from the base URL scheme" do
      expect { described_class.new(base_url: "https://allure.example", protocol: "http") }
        .to raise_error(described_class::InvalidBaseUrl, /match/)
    end

    it "tolerates a trailing slash" do
      expect(described_class.new(base_url: "https://allure.example/").base_url)
        .to eq("https://allure.example")
    end
  end

  describe "environment defaults" do
    it "disables federation by default in production" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
      with_env("FEDERATION_ENABLED" => nil) do
        expect(described_class).not_to be_enabled
      end
    end

    it "honours FEDERATION_ENABLED" do
      with_env("FEDERATION_ENABLED" => "false") do
        expect(described_class).not_to be_enabled
      end

      with_env("FEDERATION_ENABLED" => "true") do
        expect(described_class).to be_enabled
      end
    end

    it "reads FEDERATION_BASE_URL" do
      config = with_env(
        "FEDERATION_BASE_URL" => "https://from-env.example",
        "FEDERATION_PROTOCOL" => "https"
      ) { described_class.new }
      expect(config.base_url).to eq("https://from-env.example")
    end

    it "reads FEDERATION_PROTOCOL and requires it to match the base URL" do
      config = with_env(
        "FEDERATION_BASE_URL" => "https://from-env.example",
        "FEDERATION_PROTOCOL" => "https"
      ) { described_class.new }

      expect(config.protocol).to eq("https")
      expect(config).to be_secure
    end

    it "rejects an environment protocol that differs from the base URL" do
      expect {
        with_env(
          "FEDERATION_BASE_URL" => "https://from-env.example",
          "FEDERATION_PROTOCOL" => "http"
        ) { described_class.new }
      }.to raise_error(described_class::InvalidBaseUrl, /match/)
    end

    it "defaults ALLOW_PRIVATE_IPS to false, so the SSRF guard is on unless asked otherwise" do
      config = with_env("ALLOW_PRIVATE_IPS" => nil) { described_class.new }
      expect(config).not_to be_allow_private_ips
    end

    it "honours ALLOW_PRIVATE_IPS for the local ring" do
      config = with_env("ALLOW_PRIVATE_IPS" => "true") { described_class.new }
      expect(config).to be_allow_private_ips
    end
  end

  describe ".restricted_enabled?" do
    it "defaults to false in every environment" do
      with_env("FEDERATION_RESTRICTED_ENABLED" => nil) do
        expect(described_class.restricted_enabled?).to be(false)
      end
    end

    it "is enabled only by a truthy value" do
      with_env("FEDERATION_RESTRICTED_ENABLED" => "true") do
        expect(described_class.restricted_enabled?).to be(true)
      end

      with_env("FEDERATION_RESTRICTED_ENABLED" => "false") do
        expect(described_class.restricted_enabled?).to be(false)
      end
    end
  end

  def with_env(vars)
    previous = vars.transform_values { |_| nil }
    vars.each_key { |k| previous[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
