# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::BestEfforts do
  let(:started_at) { Time.utc(2026, 9, 14, 8, 0, 0) }
  let(:segment_class) { Data.define(:position, :started_at, :distance, :points) }

  def latitude_for(metres) = 45.0 + (metres / 111_320.0)

  def segment(points, position: 0)
    segment_class.new(position:, started_at:, distance: points.last.fetch("d").to_f, points:)
  end

  # A straight track with a constant pace: each step advances `step` metres in
  # `seconds_per_step`, so expected effort times are exact.
  def linear_points(distance:, step:, seconds_per_step:)
    (0..(distance / step).round).map do |index|
      metres = index * step
      { "t" => index * seconds_per_step, "d" => metres.to_f, "lat" => latitude_for(metres), "lon" => 6.0 }
    end
  end

  def find(segments, distances)
    described_class.find(segments:, distances:, workout_started_at: started_at)
  end

  describe "profiles" do
    it "maps the run family to its ordered distances, marathon included" do
      expect(described_class.profile_for("trail")).to eq("run")
      keys = described_class.distances_for("running").map(&:first)

      expect(keys.first).to eq("m400")
      expect(keys).to include("half_marathon", "km30")
      expect(keys.last).to eq("marathon")
    end

    it "maps the ride family to its ordered distances" do
      expect(described_class.profile_for("mountain_biking")).to eq("ride")
      expect(described_class.profile_for("cycling_road")).to eq("ride")
      expect(described_class.profile_for("cycling_electric")).to eq("ride")
      expect(described_class.distances_for("cycling").map(&:first))
        .to eq(%w[mi5 km10 mi10 km20 km30 km40 km50 km80 mi50])
    end

    it "maps the row family to the Concept2 standard distances" do
      expect(described_class.profile_for("rowing")).to eq("row")
      expect(described_class.profile_for("rowing_virtual")).to eq("row")
      expect(described_class.distances_for("rowing").map(&:first))
        .to eq(%w[m500 km1 km2 km5 km6 km10 half_marathon marathon])
    end

    it "returns no distances for a sport without a profile" do
      expect(described_class.distances_for("kayaking")).to eq([])
    end
  end

  describe ".find" do
    it "returns the exact elapsed time for each covered distance" do
      # 10 m/s: one kilometre per 100 seconds.
      segments = [ segment(linear_points(distance: 5_000, step: 100, seconds_per_step: 10)) ]

      efforts = find(segments, [ [ "km1", 1_000.0 ], [ "km5", 5_000.0 ] ])

      expect(efforts.map(&:distance_key)).to eq([ "km1", "km5" ])
      expect(efforts.map(&:duration_seconds)).to eq([ 100, 500 ])
    end

    it "interpolates boundaries that fall between recorded points" do
      segments = [ segment(linear_points(distance: 1_500, step: 300, seconds_per_step: 30)) ]

      effort = find(segments, [ [ "km1", 1_000.0 ] ]).first

      expect(effort.duration_seconds).to eq(100)
      expect(effort.end_offset_meters).to eq(1_000.0)
    end

    it "rounds sub-second distances like the 400 m" do
      segments = [ segment(linear_points(distance: 400, step: 50, seconds_per_step: 8.25)) ]

      expect(find(segments, [ [ "m400", 400.0 ] ]).first.duration_seconds).to eq(66)
    end

    it "finds the fastest window when the pace varies" do
      points = [ { "t" => 0.0, "d" => 0.0, "lat" => latitude_for(0), "lon" => 6.0 } ]
      distance = 0.0
      time = 0.0
      20.times do |index|
        time += index < 10 ? 20 : 10
        distance += 100
        points << { "t" => time, "d" => distance.to_f, "lat" => latitude_for(distance), "lon" => 6.0 }
      end

      effort = find([ segment(points) ], [ [ "km1", 1_000.0 ] ]).first

      expect(effort.duration_seconds).to eq(100)
      expect(effort.start_offset_meters).to eq(1_000.0)
    end

    it "never bridges a recording pause" do
      first = segment(linear_points(distance: 600, step: 100, seconds_per_step: 10), position: 0)
      second = segment_class.new(
        position: 1,
        started_at: started_at + 3_600,
        distance: 600.0,
        points: linear_points(distance: 600, step: 100, seconds_per_step: 10)
      )

      expect(find([ first, second ], [ [ "km1", 1_000.0 ] ])).to be_empty
    end

    it "omits distances the workout cannot cover" do
      segments = [ segment(linear_points(distance: 300, step: 100, seconds_per_step: 10)) ]

      expect(find(segments, [ [ "km1", 1_000.0 ] ])).to be_empty
    end

    it "returns the rowing distances a single segment covers" do
      segments = [ segment(linear_points(distance: 6_000, step: 100, seconds_per_step: 10)) ]

      efforts = find(segments, described_class.distances_for("rowing"))

      expect(efforts.map(&:distance_key)).to eq(%w[m500 km1 km2 km5 km6])
      expect(efforts.map(&:duration_seconds)).to eq([ 50, 100, 200, 500, 600 ])
    end

    it "interpolates the marathon distance" do
      segments = [ segment(linear_points(distance: 45_000, step: 1_000, seconds_per_step: 100)) ]

      effort = find(segments, [ [ "marathon", 42_195.0 ] ]).first

      expect(effort.distance_meters).to eq(42_195.0)
      expect(effort.duration_seconds).to eq(4_220)
    end
  end
end
