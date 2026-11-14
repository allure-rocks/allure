# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe Allure::Push::Config do
  it "is enabled only with a complete, well-formed VAPID configuration" do
    with_push_env { expect(described_class).to be_enabled }
    with_push_env(push_env("VAPID_SUBJECT" => nil)) { expect(described_class).not_to be_enabled }
    with_push_env(push_env("VAPID_PRIVATE_KEY" => "")) { expect(described_class).not_to be_enabled }
    with_push_env(push_env("VAPID_PUBLIC_KEY" => described_class.encode("x" * 65))) do
      expect(described_class).not_to be_enabled
    end
    with_push_env(push_env("VAPID_SUBJECT" => "operator@allure.test")) { expect(described_class).not_to be_enabled }
  end

  it "defaults to the official relay and normalizes the listed origins" do
    with_push_env { expect(described_class.relay_origins).to eq([ "https://push.allure.rocks" ]) }
    with_push_env(push_env("PUSH_RELAY_ORIGINS" => " https://Relay.Example:443/ , https://relay.example:8443")) do
      expect(described_class.relay_origins).to eq([ "https://relay.example", "https://relay.example:8443" ])
      expect(described_class.relay_origin?("https://relay.example:8443/v1/push/abc")).to be(true)
      expect(described_class.relay_origin?("https://relay.example:9443/v1/push/abc")).to be(false)
      expect(described_class.relay_origin?("https://push.allure.rocks/v1/push/abc")).to be(false)
    end
  end

  it "accepts a plain-HTTP relay outside production only" do
    with_push_env(push_env("PUSH_RELAY_ORIGINS" => "http://localhost:8787")) do
      expect(described_class.relay_origins).to eq([ "http://localhost:8787" ])
      allow(Rails.env).to receive(:production?).and_return(true)
      expect(described_class.relay_origins).to be_empty
    end
  end

  it "gives the relay and the app the public key in unpadded base64url, whatever the environment holds" do
    key = PushHelpers::VAPID[:public_key]
    standard = Base64.strict_encode64(described_class.decode(key))

    with_push_env(push_env("VAPID_PUBLIC_KEY" => standard)) { expect(described_class.public_key_param).to eq(key) }
    with_push_env(push_env("VAPID_PUBLIC_KEY" => "#{key}=")) { expect(described_class.public_key_param).to eq(key) }
  end

  it "generates a P-256 key pair in unpadded base64url" do
    pair = described_class.generate_key_pair

    expect(described_class.decode(pair[:public_key]).bytesize).to eq(65)
    expect(described_class.decode(pair[:public_key]).getbyte(0)).to eq(4)
    expect(described_class.decode(pair[:private_key]).bytesize).to eq(32)
    expect(pair.values.join).not_to include("=")
  end

  describe "push:vapid_keys" do
    before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("push:vapid_keys") }

    it "prints a fresh pair ready for the environment" do
      output = capture_stdout { Rake::Task["push:vapid_keys"].execute }

      public_key = output[/^VAPID_PUBLIC_KEY=(\S+)$/, 1]
      private_key = output[/^VAPID_PRIVATE_KEY=(\S+)$/, 1]
      with_push_env(push_env("VAPID_PUBLIC_KEY" => public_key, "VAPID_PRIVATE_KEY" => private_key)) do
        expect(described_class).to be_enabled
      end
    end

    def capture_stdout
      original = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original
    end
  end
end
