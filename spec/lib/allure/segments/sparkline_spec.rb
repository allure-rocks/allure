# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Segments::Sparkline do
  it "draws the line and its area across the box, highest elevation at the top" do
    profile = [ { "d" => 0.0, "ele" => 100.0 }, { "d" => 500.0, "ele" => 150.0 }, { "d" => 1_000.0, "ele" => 200.0 } ]

    result = described_class.new(profile, width: 100, height: 20, padding: 0).call

    expect(result.line).to eq("M0.0 20.0 L50.0 10.0 L100.0 0.0")
    expect(result.area).to eq("M0.0 20.0 L50.0 10.0 L100.0 0.0 L100.0 20.0 L0.0 20.0 Z")
    expect(result).to have_attributes(min_elevation: 100.0, max_elevation: 200.0)
  end

  it "centres a nearly flat course instead of stretching its noise" do
    profile = [ { "d" => 0.0, "ele" => 100.0 }, { "d" => 1_000.0, "ele" => 102.0 } ]

    result = described_class.new(profile, width: 100, height: 20, padding: 0).call

    expect(result.line).to eq("M0.0 11.0 L100.0 9.0")
  end

  it "skips missing elevations and refuses a profile it cannot draw" do
    gapped = [ { "d" => 0.0, "ele" => 100.0 }, { "d" => 10.0, "ele" => nil }, { "d" => 20.0, "ele" => 120.0 } ]

    expect(described_class.new(gapped, width: 10, height: 10, padding: 0).call.line).to eq("M0.0 10.0 L10.0 0.0")
    expect(described_class.new(nil, width: 10, height: 10).call).to be_nil
    expect(described_class.new([], width: 10, height: 10).call).to be_nil
    expect(described_class.new([ { "d" => 0.0, "ele" => 1.0 } ], width: 10, height: 10).call).to be_nil
  end
end
