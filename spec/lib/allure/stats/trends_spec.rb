# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Stats::Trends do
  def bucket(period:, sport_id: 1, workouts: 1, distance: 1000.0, duration: 600, ascent: 10.0)
    {
      period:,
      sport_id:,
      total_workouts: workouts,
      total_distance: distance,
      total_duration: duration,
      total_ascent: ascent
    }
  end

  describe "#series" do
    it "zero-fills a daily window ending on the given date" do
      rows = described_class.new([ bucket(period: Date.new(2026, 3, 10)) ])
        .series(periods: 3, ending_on: Date.new(2026, 3, 12), granularity: :day)

      expect(rows.map { |row| row[:period] }).to eq([ Date.new(2026, 3, 10), Date.new(2026, 3, 11), Date.new(2026, 3, 12) ])
      expect(rows.map { |row| row[:workouts] }).to eq([ 1, 0, 0 ])
      expect(rows.first[:distance]).to eq(1000.0)
      expect(rows.last[:sports]).to eq({})
    end

    it "sums across sports and keeps the per-sport detail" do
      buckets = [
        bucket(period: Date.new(2026, 3, 10), sport_id: 1, distance: 1000.0),
        bucket(period: Date.new(2026, 3, 10), sport_id: 2, distance: 500.0, workouts: 2)
      ]
      rows = described_class.new(buckets).series(periods: 1, ending_on: Date.new(2026, 3, 10))

      expect(rows.sole[:distance]).to eq(1500.0)
      expect(rows.sole[:workouts]).to eq(3)
      expect(rows.sole[:sports]).to eq(
        { 1 => { workouts: 1, distance: 1000.0, duration: 600, ascent: 10.0 },
          2 => { workouts: 2, distance: 500.0, duration: 600, ascent: 10.0 } }
      )
    end

    it "ignores buckets outside the window" do
      buckets = [ bucket(period: Date.new(2026, 2, 1)), bucket(period: Date.new(2026, 3, 12)) ]
      rows = described_class.new(buckets).series(periods: 2, ending_on: Date.new(2026, 3, 12))

      expect(rows.map { |row| row[:workouts] }).to eq([ 0, 1 ])
    end

    it "aligns monthly windows on calendar months" do
      rows = described_class.new([ bucket(period: Date.new(2026, 1, 1), distance: 42.0) ])
        .series(periods: 3, ending_on: Date.new(2026, 3, 18), granularity: :month)

      expect(rows.map { |row| row[:period] }).to eq([ Date.new(2026, 1, 1), Date.new(2026, 2, 1), Date.new(2026, 3, 1) ])
      expect(rows.map { |row| row[:distance] }).to eq([ 42.0, 0.0, 0.0 ])
    end

    it "aligns yearly windows on January 1st" do
      rows = described_class.new([ bucket(period: Date.new(2024, 1, 1), distance: 42.0) ])
        .series(periods: 3, ending_on: Date.new(2026, 9, 18), granularity: :year)

      expect(rows.map { |row| row[:period] }).to eq([ Date.new(2024, 1, 1), Date.new(2025, 1, 1), Date.new(2026, 1, 1) ])
      expect(rows.map { |row| row[:distance] }).to eq([ 42.0, 0.0, 0.0 ])
    end

    it "steps weekly windows by seven days from the aligned end date" do
      rows = described_class.new([ bucket(period: Date.new(2026, 3, 2), workouts: 4) ])
        .series(periods: 3, ending_on: Date.new(2026, 3, 16), granularity: :week)

      expect(rows.map { |row| row[:period] }).to eq([ Date.new(2026, 3, 2), Date.new(2026, 3, 9), Date.new(2026, 3, 16) ])
      expect(rows.map { |row| row[:workouts] }).to eq([ 4, 0, 0 ])
    end

    it "rejects unknown granularities" do
      expect { described_class.new([]).series(periods: 1, ending_on: Date.current, granularity: :hour) }
        .to raise_error(ArgumentError)
    end
  end

  describe ".totals" do
    it "sums a zero-filled series into the metric shape" do
      rows = [
        { workouts: 1, distance: 1000.0, duration: 600, ascent: 10.0 },
        { workouts: 2, distance: 500.0, duration: 300, ascent: 5.0 }
      ]

      expect(described_class.totals(rows)).to eq(workouts: 3, distance: 1500.0, duration: 900, ascent: 15.0)
    end
  end

  describe ".between" do
    it "keeps the rows inside the inclusive range" do
      rows = [ { period: Date.new(2026, 3, 1) }, { period: Date.new(2026, 3, 15) }, { period: Date.new(2026, 4, 1) } ]

      expect(described_class.between(rows, Date.new(2026, 3, 1)..Date.new(2026, 3, 31)).map { |row| row[:period] })
        .to eq([ Date.new(2026, 3, 1), Date.new(2026, 3, 15) ])
    end

    it "passes every row through without a range" do
      rows = [ { period: Date.new(2026, 3, 1) } ]

      expect(described_class.between(rows, nil)).to eq(rows)
    end
  end

  describe ".sport_totals" do
    it "aggregates the per-sport detail across rows" do
      rows = described_class.new([
        bucket(period: Date.new(2026, 3, 10), sport_id: 1, distance: 1000.0),
        bucket(period: Date.new(2026, 3, 11), sport_id: 1, distance: 500.0),
        bucket(period: Date.new(2026, 3, 11), sport_id: 2, distance: 9000.0)
      ]).series(periods: 2, ending_on: Date.new(2026, 3, 11))

      totals = described_class.sport_totals(rows)

      expect(totals[1][:distance]).to eq(1500.0)
      expect(totals[1][:workouts]).to eq(2)
      expect(totals[2][:distance]).to eq(9000.0)
    end
  end

  describe ".week_start_on_or_before" do
    it "anchors a Monday week" do
      expect(described_class.week_start_on_or_before(Date.new(2026, 3, 18), "monday")).to eq(Date.new(2026, 3, 16))
    end

    it "anchors a Sunday week" do
      expect(described_class.week_start_on_or_before(Date.new(2026, 3, 18), "sunday")).to eq(Date.new(2026, 3, 15))
    end
  end

  describe ".compare" do    it "reports an upward move against the previous window" do
      expect(described_class.compare(current: 120.0, previous: 100.0))
        .to include(percent: 20.0, direction: :up)
    end

    it "reports a downward move against the previous window" do
      expect(described_class.compare(current: 80.0, previous: 100.0))
        .to include(percent: -20.0, direction: :down)
    end

    it "treats a negligible move as flat" do
      expect(described_class.compare(current: 100.0, previous: 100.2))
        .to include(direction: :flat)
    end

    it "has no comparison when the previous window is empty" do
      expect(described_class.compare(current: 100.0, previous: 0.0))
        .to include(percent: nil, direction: :none)
    end
  end

  describe "#week_to_date" do
    it "reads the current week bucket and averages the four previous weeks" do
      buckets = [
        bucket(period: Date.new(2026, 3, 16), distance: 30_000.0),
        bucket(period: Date.new(2026, 3, 9), distance: 10_000.0),
        bucket(period: Date.new(2026, 3, 2), distance: 20_000.0),
        bucket(period: Date.new(2026, 2, 23), distance: 0.0, workouts: 0),
        bucket(period: Date.new(2026, 2, 16), distance: 10_000.0)
      ]
      result = described_class.new(buckets).week_to_date(week_start: "monday", today: Date.new(2026, 3, 18))

      expect(result[:current][:distance]).to eq(30_000.0)
      expect(result[:average][:distance]).to eq(10_000.0)
    end

    it "anchors the current week on the user's week start" do
      buckets = [ bucket(period: Date.new(2026, 3, 15), distance: 5_000.0) ]
      result = described_class.new(buckets).week_to_date(week_start: "sunday", today: Date.new(2026, 3, 18))

      expect(result[:current][:distance]).to eq(5_000.0)
    end
  end

  describe "#streaks" do
    it "counts consecutive active weeks back from the current week" do
      buckets = [
        bucket(period: Date.new(2026, 3, 16)),
        bucket(period: Date.new(2026, 3, 9)),
        bucket(period: Date.new(2026, 3, 2)),
        bucket(period: Date.new(2026, 2, 9))
      ]
      result = described_class.new(buckets).streaks(week_start: "monday", today: Date.new(2026, 3, 18))

      expect(result).to eq(current: 3, longest: 3)
    end

    it "keeps the streak alive while the current week is still empty" do
      buckets = [ bucket(period: Date.new(2026, 3, 9)), bucket(period: Date.new(2026, 3, 2)) ]
      result = described_class.new(buckets).streaks(week_start: "monday", today: Date.new(2026, 3, 18))

      expect(result[:current]).to eq(2)
    end

    it "reports zero when neither the current nor the previous week is active" do
      buckets = [ bucket(period: Date.new(2026, 3, 2)) ]
      result = described_class.new(buckets).streaks(week_start: "monday", today: Date.new(2026, 3, 18))

      expect(result).to eq(current: 0, longest: 1)
    end

    it "follows the Sunday-start preference" do
      buckets = [ bucket(period: Date.new(2026, 3, 15)), bucket(period: Date.new(2026, 3, 8)) ]
      result = described_class.new(buckets).streaks(week_start: "sunday", today: Date.new(2026, 3, 18))

      expect(result[:current]).to eq(2)
    end
  end

  describe "#active_days" do
    it "counts distinct active days in the trailing window" do
      buckets = [
        bucket(period: Date.new(2026, 3, 18), sport_id: 1),
        bucket(period: Date.new(2026, 3, 18), sport_id: 2),
        bucket(period: Date.new(2026, 3, 16)),
        bucket(period: Date.new(2026, 2, 1))
      ]
      result = described_class.new(buckets).active_days(window: 7, today: Date.new(2026, 3, 18))

      expect(result).to eq(count: 2, window: 7)
    end
  end
end
