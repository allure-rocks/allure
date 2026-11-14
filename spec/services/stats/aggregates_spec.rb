# frozen_string_literal: true

require "rails_helper"

RSpec.describe Stats::Aggregates do
  let(:user) { create(:user, time_zone: "Europe/Paris", week_start: "monday") }
  let(:sport1) { create(:sport) }
  let(:sport2) { create(:sport) }

  # August is CEST (UTC+2) in Paris. W1 at Mon 23:00 UTC is Tue 01:00 in
  # Paris, so UTC-day and Paris-day bucketing disagree by design.
  def create_workout(started_at:, sport:, distance:, moving:, ascent:, descent:, calories:, average_speed:, average_pace:)
    create(:workout, user:, sport:, started_at:,
      distance:, ascent:, descent:, calories:,
      duration: moving + 100, moving_time: moving, pause_time: 100,
      average_speed:, average_pace:)
  end

  before do
    create_workout(started_at: Time.utc(2026, 8, 31, 23, 0), sport: sport1,
      distance: 1000, moving: 600, ascent: 50, descent: 10, calories: 100, average_speed: 5.0, average_pace: 200)
    create_workout(started_at: Time.utc(2026, 9, 1, 10, 0), sport: sport1,
      distance: 2000, moving: 900, ascent: 30, descent: 20, calories: 200, average_speed: 6.0, average_pace: 180)
    create_workout(started_at: Time.utc(2026, 9, 7, 10, 0), sport: sport2,
      distance: 500, moving: 300, ascent: 10, descent: 5, calories: 50, average_speed: 4.0, average_pace: nil)
  end

  describe "#by_time day" do
    it "buckets in the viewer's time zone, not UTC, split by sport" do
      rows = described_class.new(user:).by_time(granularity: "day")

      expect(rows.map { |row| [ row[:period], row[:sport_id] ] }).to eq([
        [ Date.new(2026, 9, 1), sport1.id ],
        [ Date.new(2026, 9, 7), sport2.id ]
      ])

      september_first = rows.first
      expect(september_first[:total_workouts]).to eq(2)
      expect(september_first[:total_distance]).to be_within(1e-6).of(3000)
      expect(september_first[:average_distance]).to be_within(1e-6).of(1500)
      expect(september_first[:total_duration]).to eq(1500)
      expect(september_first[:average_duration]).to be_within(1e-6).of(750)
      expect(september_first[:total_ascent]).to be_within(1e-6).of(80)
      expect(september_first[:total_calories]).to eq(300)
      expect(september_first[:average_speed]).to be_within(1e-6).of(5.5)
      expect(september_first[:average_pace]).to be_within(1e-6).of(190)
    end

    it "leaves average pace nil when no workout in the bucket has one" do
      rows = described_class.new(user:).by_time(granularity: "day")

      expect(rows.last[:average_pace]).to be_nil
    end
  end

  describe "#by_time week" do
    it "anchors Monday weeks on Monday by default" do
      rows = described_class.new(user:).by_time(granularity: "week")

      expect(rows.map { |row| [ row[:period], row[:sport_id] ] }).to eq([
        [ Date.new(2026, 8, 31), sport1.id ],
        [ Date.new(2026, 9, 7), sport2.id ]
      ])
      expect(rows.first[:total_workouts]).to eq(2)
    end

    it "names the workout of a bucket holding a single one" do
      rows = described_class.new(user:).by_time(granularity: "week")
      single = user.workouts.find_by!(sport: sport2)

      expect(rows.first[:workout_id]).to be_nil
      expect(rows.last[:workout_id]).to eq(single.to_param)
    end

    it "anchors Sunday weeks on Sunday when configured" do
      user.update!(week_start: "sunday")

      rows = described_class.new(user:).by_time(granularity: "week")

      expect(rows.map { |row| [ row[:period], row[:sport_id] ] }).to eq([
        [ Date.new(2026, 8, 30), sport1.id ],
        [ Date.new(2026, 9, 6), sport2.id ]
      ])
    end
  end

  describe "#by_time month" do
    it "groups by calendar month in the viewer's zone" do
      rows = described_class.new(user:).by_time(granularity: "month")

      expect(rows.map { |row| [ row[:period], row[:sport_id] ] }).to eq([
        [ Date.new(2026, 9, 1), sport1.id ],
        [ Date.new(2026, 9, 1), sport2.id ]
      ])
    end
  end

  describe "#by_time year" do
    it "groups by calendar year in the viewer's zone" do
      rows = described_class.new(user:).by_time(granularity: "year")

      expect(rows.map { |row| row[:period] }).to eq([ Date.new(2026, 1, 1), Date.new(2026, 1, 1) ])
    end
  end

  describe "#by_sport" do
    it "rolls up all time per sport with no period" do
      rows = described_class.new(user:).by_sport

      expect(rows.map { |row| row[:sport_id] }).to contain_exactly(sport1.id, sport2.id)
      expect(rows.none? { |row| row.key?(:period) }).to be(true)

      sport1_row = rows.find { |row| row[:sport_id] == sport1.id }
      expect(sport1_row[:total_workouts]).to eq(2)
      expect(sport1_row[:total_distance]).to be_within(1e-6).of(3000)
    end
  end

  describe "filtering and edge cases" do
    it "scopes to one sport when asked" do
      rows = described_class.new(user:).by_time(granularity: "month", sport_id: sport2.id)

      expect(rows.map { |row| row[:sport_id] }).to eq([ sport2.id ])
    end

    it "rejects an unknown granularity" do
      expect { described_class.new(user:).by_time(granularity: "decade") }.to raise_error(ArgumentError)
    end

    it "scans beyond the recent-workout cap only when the limit is lifted" do
      stub_const("Stats::Aggregates::RECENT_LIMIT", 1)

      capped = described_class.new(user:).by_time(granularity: "month")
      full = described_class.new(user:).by_time(granularity: "month", limit: nil)

      expect(capped.map { |row| row[:sport_id] }).to eq([ sport2.id ])
      expect(full.map { |row| row[:sport_id] }).to contain_exactly(sport1.id, sport2.id)
      expect(full.sum { |row| row[:total_workouts] }).to eq(3)
    end

    it "returns an empty list with no workouts" do
      expect(described_class.new(user: create(:user)).by_time(granularity: "day")).to eq([])
      expect(described_class.new(user:).by_sport).not_to be_empty
    end
  end
end
