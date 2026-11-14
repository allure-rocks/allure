# frozen_string_literal: true

module Allure
  module Stats
    # The personal hub's pulse: one relative intensity score per zero-filled
    # week of the whole history (DESIGN.md §15.1). A week's effort is the mean
    # of its moving time, distance and ascent, each taken as a share of the
    # history's strongest week for that component; the scores are that effort
    # relative to the strongest week's, scaled to 0..100 — so 100 is always
    # the hardest week ever recorded and a week half as long, half as far and
    # half as steep as it scores 50. A component nobody ever recorded (no
    # ascent on a pool history) is left out instead of dragging every score
    # down. The selected period never enters the scoring: it only scopes the
    # `range` filters, so switching windows cannot redraw the waveform. Pure:
    # plain hashes in, plain hashes out, no Active Record.
    class Intensity
      COMPONENTS = %i[duration distance ascent].freeze
      SCALE = 100

      attr_reader :rows, :components

      def initialize(rows)
        source = Array(rows)
        @components = COMPONENTS.select { |component| source.any? { |row| row[component].to_f.positive? } }
        maxima = @components.to_h { |component| [ component, source.map { |row| row[component].to_f }.max ] }
        efforts = source.map { |row| effort(row, maxima) }
        strongest = efforts.max || 0.0
        @rows = source.zip(efforts).map { |row, value| score_row(row, strongest.positive? ? value / strongest : 0.0) }
      end

      # The rows whose week overlaps the inclusive date range — a period rarely
      # starts on a week start, and the week carrying its first days belongs to
      # the highlighted span — or every row when no range is given.
      def within(range = nil)
        return @rows if range.nil?

        @rows.select do |row|
          start = row[:period].to_date
          start <= range.end && start + 6 >= range.begin
        end
      end

      # The strongest active week within the range (the whole history without
      # one), the earliest on a tie, or nil when that window holds no activity.
      def peak(range = nil)
        active = within(range).reject { |row| row[:rest] }
        return nil if active.empty?

        best = active.map { |row| row[:score] }.max
        active.find { |row| row[:score] == best }
      end

      def active_count(range = nil)
        within(range).count { |row| !row[:rest] }
      end

      def total_count(range = nil)
        within(range).size
      end

      private

      def effort(row, maxima)
        return 0.0 if @components.empty?

        @components.sum { |component| row[component].to_f / maxima.fetch(component) } / @components.size
      end

      def score_row(row, share)
        workouts = row[:workouts].to_i

        {
          period: row[:period],
          score: workouts.positive? ? [ (share * SCALE).round, 1 ].max : 0,
          rest: workouts.zero?,
          workouts:,
          # Distinct sports practiced that week, for the facts line
          # (DESIGN.md §15.1).
          sports: row[:sports]&.size.to_i,
          distance: row[:distance].to_f,
          duration: row[:duration].to_i,
          ascent: row[:ascent].to_f
        }
      end
    end
  end
end
