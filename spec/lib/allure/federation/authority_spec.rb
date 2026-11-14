# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Federation::Authority do
  describe ".domain" do
    it "folds the host case and keeps a non-default port" do
      expect(described_class.domain("https://REMOTE.Example/users/demo")).to eq("remote.example")
      expect(described_class.domain("http://Remote.Example:8443/users/demo")).to eq("remote.example:8443")
    end

    it "drops the default port" do
      expect(described_class.domain("https://Remote.Example:443/users/demo")).to eq("remote.example")
    end

    it "returns nil without a host" do
      expect(described_class.domain("not-a-uri")).to be_nil
    end
  end

  describe ".normalize_uri" do
    it "folds the scheme and host case but preserves the path case" do
      expect(described_class.normalize_uri("HTTPS://REMOTE.Example/Users/Demo")).to eq("https://remote.example/Users/Demo")
      expect(described_class.normalize_uri("https://Remote.Example:8443/Users/Demo")).to eq("https://remote.example:8443/Users/Demo")
    end

    it "returns the input unchanged when it has no host" do
      expect(described_class.normalize_uri("not-a-uri")).to eq("not-a-uri")
    end
  end

  describe ".site" do
    it "keeps the last two labels so wildcard subdomains share one site" do
      expect(described_class.site("https://A1.Attacker.Example:8443/users/x")).to eq("attacker.example")
      expect(described_class.site("https://a2.attacker.example/users/x")).to eq("attacker.example")
      expect(described_class.site("https://remote.example/users/demo")).to eq("remote.example")
    end

    it "keeps an IP literal whole" do
      expect(described_class.site("https://93.184.216.34/users/x")).to eq("93.184.216.34")
      expect(described_class.site("https://[2001:db8::1]/users/x")).to eq("[2001:db8::1]")
    end

    it "returns nil without a host" do
      expect(described_class.site("not-a-uri")).to be_nil
    end
  end
end
