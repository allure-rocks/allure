# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Funding::Providers::Registry, :funding do
  let(:registry) { described_class.new }
  let(:adapter) { Class.new { def self.slug = "test_provider"; def self.enabled? = true } }

  it "exposes only registered, enabled adapters while the master switch is on" do
    registry.register(adapter)
    expect(registry.fetch("test_provider")).to eq(adapter)
    expect(registry.fetch("unknown")).to be_nil
    allow(adapter).to receive(:enabled?).and_return(false)
    expect(registry.enabled).to be_empty
    expect(registry.fetch("test_provider")).to be_nil
    allow(adapter).to receive(:enabled?).and_return(true)
    ENV["FUNDING_ENABLED"] = "false"
    expect(registry.enabled).to be_empty
    expect(registry.fetch("test_provider")).to be_nil
  end

  it "rejects duplicate identifiers from different adapters and the reserved manual provider" do
    registry.register(adapter)
    # Re-registering the same adapter is a no-op: to_prepare re-runs after
    # every code reload while the registry constant itself is recreated.
    expect { registry.register(adapter) }.not_to raise_error
    expect(registry.registered("test_provider")).to eq(adapter)

    other = Class.new { def self.slug = "test_provider"; def self.enabled? = true }
    expect { registry.register(other) }.to raise_error(ArgumentError)
    allow(adapter).to receive(:slug).and_return("manual")
    expect { registry.register(adapter) }.to raise_error(ArgumentError)
  end
end
