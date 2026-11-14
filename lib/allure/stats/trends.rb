# frozen_string_literal: true

module Allure
  module Stats
    # Pure series math over the sparse, viewer-timezoned buckets produced by
    # Stats::Aggregates. Zero-fills windows for sparklines and the stacked
    # trend chart, compares rolling periods, and derives the regularity
    # figures (streaks, active days, week-to-date). No Active Record and no
    # view logic: every method takes plain hashes and returns plain hashes.
    class Trends
      METRICS = %i[workouts distance duration ascent].freeze
      GRANULARITIES = %i[day week month year].freeze

      def initialize(buckets)
        @buckets = Array(buckets)
      end

      # Zero-filled rows for the last `periods` buckets ending on `ending_on`.
      # Week windows expect `ending_on` to already be the viewer's week start;
      # month windows accept any date inside the target month.
      #
      # Each row carries the totals for the window plus a `:sports` hash of
      # per-sport totals, so one pass feeds both the sparklines and the
      # stacked trend chart.
      def series(periods:, ending_on:, granularity: :day)
        periods = Integer(periods)
        raise ArgumentError, "periods must be positive" if periods.negative?
        raise ArgumentError, "unknown granularity: #{granularity.inspect}" unless GRANULARITIES.include?(granularity.to_sym)

        starts = bucket_starts(periods:, ending_on:, granularity:)
        rows = starts.to_h { |period| [ period, empty_row(period) ] }
        @buckets.each do |bucket|
          row = rows[bucket[:period]]
          add!(row, bucket) if row
        end
        starts.map { |period| rows.fetch(period) }
      end

      # The current calendar week's totals next to the mean of the four
      # complete weeks before it. `week_start` is the user preference
      # ("monday" or "sunday"); zero weeks count in the average.
      def week_to_date(week_start:, today: Date.current)
        start = week_start_on_or_before(today, week_start)
        current = totals_for(period: start)
        previous = (1..4).map { |offset| totals_for(period: start - offset * 7) }
        average = {
          workouts: previous.sum { |row| row[:workouts] } / 4.0,
          distance: previous.sum { |row| row[:distance] } / 4.0,
          duration: previous.sum { |row| row[:duration] } / 4.0
        }
        { current:, average: }
      end

      # Consecutive active weeks. A current week without a workout does not
      # break the streak until the week is over: the run may start last week.
      def streaks(week_start:, today: Date.current)
        active = @buckets
          .select { |bucket| bucket[:total_workouts].to_i.positive? }
          .map { |bucket| bucket[:period] }
          .uniq
        set = active.to_h { |period| [ period, true ] }
        start = week_start_on_or_before(today, week_start)
        start -= 7 unless set[start]
        { current: run_from(set, start), longest: longest_run(active) }
      end

      # Distinct days with at least one workout over the trailing window.
      def active_days(window:, today: Date.current)
        first = today.to_date - (window - 1)
        days = @buckets
          .select { |bucket| bucket[:total_workouts].to_i.positive? && bucket[:period] >= first && bucket[:period] <= today }
          .map { |bucket| bucket[:period] }
          .uniq
        { count: days.size, window: }
      end

      # Sum of a zero-filled series, in the same shape as the per-row totals.
      def self.totals(rows)
        rows.each_with_object({ workouts: 0, distance: 0.0, duration: 0, ascent: 0.0 }) do |row, sum|
          sum[:workouts] += row[:workouts]
          sum[:distance] += row[:distance]
          sum[:duration] += row[:duration]
          sum[:ascent] += row[:ascent]
        end
      end

      # The rows whose period falls inside the inclusive range.
      def self.between(rows, range)
        return rows if range.nil?

        rows.select { |row| range.cover?(row[:period]) }
      end

      # Per-sport totals across a series, one hash per sport id.
      def self.sport_totals(rows)
        totals = {}
        rows.each do |row|
          row[:sports].each do |sport_id, values|
            sum = totals[sport_id] ||= { workouts: 0, distance: 0.0, duration: 0, ascent: 0.0 }
            sum[:workouts] += values[:workouts]
            sum[:distance] += values[:distance]
            sum[:duration] += values[:duration]
            sum[:ascent] += values[:ascent]
          end
        end
        totals
      end

      # The Monday or Sunday on or before `date`, per the user preference.
      def self.week_start_on_or_before(date, week_start)
        date = date.to_date
        return date - date.wday if week_start.to_s == "sunday"

        date - ((date.wday + 6) % 7)
      end

      def self.compare(current:, previous:)
        current = current.to_f
        previous = previous.to_f
        return { current:, previous:, percent: nil, direction: :none } if previous <= 0

        percent = ((current - previous) / previous) * 100.0
        direction = if percent > 0.5
          :up
        elsif percent < -0.5
          :down
        else
          :flat
        end
        { current:, previous:, percent:, direction: }
      end

      private

      def bucket_starts(periods:, ending_on:, granularity:)
        ending_on = ending_on.to_date
        case granularity.to_sym
        when :day
          (periods - 1).downto(0).map { |offset| ending_on - offset }
        when :week
          (periods - 1).downto(0).map { |offset| ending_on - offset * 7 }
        when :month
          (periods - 1).downto(0).map { |offset| (ending_on << offset).beginning_of_month }
        when :year
          (periods - 1).downto(0).map { |offset| Date.new(ending_on.year - offset, 1, 1) }
        end
      end

      def empty_row(period)
        { period:, workouts: 0, distance: 0.0, duration: 0, ascent: 0.0, sports: {} }
      end

      def add!(row, bucket)
        row[:workouts] += bucket[:total_workouts].to_i
        row[:distance] += bucket[:total_distance].to_f
        row[:duration] += bucket[:total_duration].to_i
        row[:ascent] += bucket[:total_ascent].to_f

        sport_id = bucket[:sport_id]
        return unless sport_id

        sport = row[:sports][sport_id] ||= { workouts: 0, distance: 0.0, duration: 0, ascent: 0.0 }
        sport[:workouts] += bucket[:total_workouts].to_i
        sport[:distance] += bucket[:total_distance].to_f
        sport[:duration] += bucket[:total_duration].to_i
        sport[:ascent] += bucket[:total_ascent].to_f
      end

      def totals_for(period:)
        totals = { workouts: 0, distance: 0.0, duration: 0 }
        @buckets.each do |bucket|
          next unless bucket[:period] == period

          totals[:workouts] += bucket[:total_workouts].to_i
          totals[:distance] += bucket[:total_distance].to_f
          totals[:duration] += bucket[:total_duration].to_i
        end
        totals
      end

      def run_from(set, start)
        length = 0
        cursor = start
        while set[cursor]
          length += 1
          cursor -= 7
        end
        length
      end

      def longest_run(dates)
        longest = 0
        current = 0
        previous = nil
        dates.sort.each do |date|
          current = previous && date == previous + 7 ? current + 1 : 1
          longest = current if current > longest
          previous = date
        end
        longest
      end

      def week_start_on_or_before(date, week_start)
        self.class.week_start_on_or_before(date, week_start)
      end
    end
  end
end
