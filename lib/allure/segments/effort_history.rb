# frozen_string_literal: true

module Allure
  module Segments
    # A viewer's own times on one course over time, one series per sport,
    # oldest first. Each entry carries its personal place (1–3, the trophy) and
    # its gap to the record; each series carries a trend. Works on any value
    # responding to `id`, `sport_id`, `workout_id`, `started_at` and
    # `elapsed_time`; never reads the database.
    class EffortHistory
      MIN_EFFORTS = 2
      PLACES = 3
      # The trend is Stats::RobustTrend over the outings: a Theil–Sen line
      # while they are few, a robust LOWESS curve beyond. It is evaluated on a
      # regular grid (plus every outing) and drawn with straight segments.
      MIN_TREND_OUTINGS = 3
      TREND_GRID = 100
      # Where the trend rests on too little, it is drawn dotted: everywhere
      # under RELIABLE_OUTINGS outings, and across a gap between two outings
      # longer than both LONG_GAP and LONG_GAP_SHARE of the history.
      RELIABLE_OUTINGS = 5
      LONG_GAP = 6 * 30 * 86_400
      LONG_GAP_SHARE = 0.15

      Entry = Data.define(:effort, :place, :gap_to_best)
      # `reliable` qualifies the stretch from this point to the next one.
      TrendPoint = Data.define(:started_at, :elapsed_time, :reliable) do
        def reliable? = reliable
      end
      Series = Data.define(:sport_id, :entries, :best, :trend)

      attr_reader :series

      def initialize(efforts)
        @series = efforts
          .sort_by { |effort| [ effort.started_at, effort.id ] }
          .group_by(&:sport_id)
          .map { |sport_id, chronological| build(sport_id, chronological) }
          .sort_by(&:best)
      end

      # One chart per sport, and a single point is no history: a sport is drawn
      # from two efforts.
      def chartable_series
        series.select { |line| line.entries.size >= MIN_EFFORTS }
      end

      def chartable?
        chartable_series.any?
      end

      def entries
        series.flat_map(&:entries).sort_by { |entry| [ entry.effort.started_at, entry.effort.id ] }
      end

      private

      def build(sport_id, chronological)
        best = chronological.map(&:elapsed_time).min
        places = ranked_places(chronological)
        entries = chronological.map do |effort|
          Entry.new(effort:, place: places[effort.id], gap_to_best: effort.elapsed_time - best)
        end
        Series.new(sport_id:, entries:, best:, trend: trend(chronological))
      end

      # The personal-place rule (PLAN_SEGMENTS.md §7.6): time, then the earlier
      # start, then the earlier row, exactly like the efforts table.
      def ranked_places(efforts)
        efforts
          .sort_by { |effort| [ effort.elapsed_time, effort.started_at, effort.id ] }
          .first(PLACES)
          .each_with_index
          .to_h { |effort, index| [ effort.id, index + 1 ] }
      end

      # Several laps of one outing (a loop) count as one value, their mean, so
      # the trend compares outings rather than the fatigue within a session.
      def trend(chronological)
        outings = chronological.group_by(&:workout_id).values.map do |laps|
          [ laps.first.started_at, laps.sum(&:elapsed_time) / laps.size.to_f ]
        end
        return [] if outings.size < MIN_TREND_OUTINGS

        origin = outings.first.first
        xs = outings.map { |started_at, _| (started_at - origin).to_f }
        span = xs.last - xs.first
        grid = trend_grid(xs, span)
        fitted = Stats::RobustTrend.fit_at(xs, outings.map(&:last), grid)
        gaps = long_gaps(xs, span)
        few = outings.size < RELIABLE_OUTINGS

        grid.each_with_index.map do |x, index|
          following = grid[index + 1] || x
          middle = (x + following) / 2
          reliable = !few && gaps.none? { |from, to| middle > from && middle < to }
          TrendPoint.new(started_at: origin + x, elapsed_time: fitted[index], reliable:)
        end
      end

      # Evenly spaced positions across the history, plus every outing, so a
      # dotted stretch starts and ends exactly on an outing.
      def trend_grid(xs, span)
        regular = (1...TREND_GRID).map { |step| xs.first + span * step / TREND_GRID }
        (regular + xs).uniq.sort
      end

      def long_gaps(xs, span)
        xs.each_cons(2).select { |from, to| to - from > LONG_GAP && to - from > LONG_GAP_SHARE * span }
      end
    end
  end
end
