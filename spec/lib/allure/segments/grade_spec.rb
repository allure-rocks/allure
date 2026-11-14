# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Segments::Grade do
  describe ".from_elevations" do
    it "is the signed net change over the distance, negative on a descent" do
      expect(described_class.from_elevations([ 300.0, 310.0, 250.0 ], distance: 1_000.0)).to be_within(0.001).of(-5.0)
      expect(described_class.from_elevations([ 100.0, 90.0, 150.0 ], distance: 500.0)).to be_within(0.001).of(10.0)
    end

    it "ignores missing elevations and needs two of them and a distance" do
      expect(described_class.from_elevations([ nil, 100.0, nil, 120.0, nil ], distance: 1_000.0)).to be_within(0.001).of(2.0)
      expect(described_class.from_elevations([ nil, 100.0 ], distance: 1_000.0)).to be_nil
      expect(described_class.from_elevations([ 100.0, 120.0 ], distance: 0)).to be_nil
    end
  end

  describe ".from_profile" do
    it "reads the stored profile and falls back to the totals without elevation" do
      profile = [ { "d" => 0.0, "ele" => 44.0 }, { "d" => 784.0, "ele" => 17.0 } ]

      expect(described_class.from_profile(profile, distance: 784.0)).to be_within(0.01).of(-3.44)
      expect(described_class.from_profile([], distance: 1_000.0, ascent: 5.0, descent: 25.0)).to be_within(0.001).of(-2.0)
      expect(described_class.from_profile(nil, distance: 1_000.0)).to be_nil
    end
  end
end
