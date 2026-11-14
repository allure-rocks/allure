# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Stats::Periods do
  let(:today) { Date.new(2026, 9, 16) } # a Wednesday

  describe ".range" do
    it "runs the week from the viewer's week start to today" do
      expect(described_class.range("week", today:)).to eq(Date.new(2026, 9, 14)..today)
      expect(described_class.range("week", today:, week_start: "sunday")).to eq(Date.new(2026, 9, 13)..today)
    end

    it "counts the rolling thirty days inclusively" do
      expect(described_class.range("days30", today:)).to eq(Date.new(2026, 8, 18)..today)
    end

    it "runs the year from January 1st" do
      expect(described_class.range("year", today:)).to eq(Date.new(2026, 1, 1)..today)
    end

    it "returns nil for all and unknown keys" do
      expect(described_class.range("all", today:)).to be_nil
      expect(described_class.range("bogus", today:)).to be_nil
    end
  end

  describe ".previous_range" do
    it "mirrors each window" do
      expect(described_class.previous_range("week", today:)).to eq(Date.new(2026, 9, 7)..Date.new(2026, 9, 13))
      expect(described_class.previous_range("week", today:, week_start: "sunday"))
        .to eq(Date.new(2026, 9, 6)..Date.new(2026, 9, 12))
      expect(described_class.previous_range("days30", today:)).to eq(Date.new(2026, 7, 19)..Date.new(2026, 8, 17))
      expect(described_class.previous_range("year", today:)).to eq(Date.new(2025, 1, 1)..Date.new(2025, 9, 16))
    end
  end
end
