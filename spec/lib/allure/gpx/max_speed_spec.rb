# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::MaxSpeed do
  def interval(duration, speed)
    Struct.new(:distance, :duration, :speed).new(duration * speed, duration, speed)
  end

  describe ".calculate" do
    it "returns nil for no intervals" do
      expect(described_class.calculate([])).to be_nil
    end

    it "returns a sole interval's speed" do
      expect(described_class.calculate([ interval(10.0, 5.0) ])).to eq(5.0)
    end

    it "dilutes a one-second GPS spike over the ten-second window" do
      intervals = Array.new(20) { interval(1.0, 5.0) }
      intervals << interval(1.0, 20.0)
      intervals.concat(Array.new(20) { interval(1.0, 5.0) })
      expect(described_class.calculate(intervals)).to eq(6.5)
    end

    it "keeps a speed sustained for ten seconds even in a long activity" do
      intervals = Array.new(100) { interval(1.0, 5.0) }
      intervals[50, 10] = Array.new(10) { interval(1.0, 15.0) }
      expect(described_class.calculate(intervals)).to eq(15.0)
    end

    it "prorates irregular intervals at the window boundary" do
      intervals = [ interval(6.0, 2.0), interval(6.0, 10.0) ]
      expect(described_class.calculate(intervals)).to eq(6.8)
    end

    it "averages the available duration when a segment is shorter than the window" do
      intervals = [ interval(1.0, 3.0), interval(1.0, 9.0) ]
      expect(described_class.calculate(intervals)).to eq(6.0)
    end

    it "includes stopped time in the sustained-speed window" do
      intervals = [ interval(1.0, 9.0), interval(1.0, 0.0), interval(1.0, 9.0) ]
      expect(described_class.calculate(intervals)).to eq(6.0)
    end

    it "returns nil when every interval has zero distance" do
      expect(described_class.calculate([ interval(1.0, 0.0) ])).to be_nil
    end
  end
end
