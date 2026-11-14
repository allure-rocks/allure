# frozen_string_literal: true

module Allure
  module Stats
    # The calendar period windows shared by the personal hub (/me) and the
    # workout list (/workouts): "week" is the calendar week anchored on the
    # viewer's week start, "days30" is the rolling thirty days, and "year" is
    # the calendar year. Pure date arithmetic on an explicit viewer calendar,
    # so a controller can turn a window into SQL bounds in the viewer's zone
    # and the hub can plot the same window in its own timezone.
    module Periods
      KEYS = %w[week days30 year].freeze

      module_function

      # Inclusive Date range of the selected period, or nil for "all" and
      # unknown keys.
      def range(key, today:, week_start: "monday")
        case key
        when "week" then Trends.week_start_on_or_before(today, week_start)..today
        when "days30" then (today - 29)..today
        when "year" then Date.new(today.year, 1, 1)..today
        end
      end

      # The window a delta compares against: the previous calendar week, the
      # previous thirty days, or the same elapsed period last year (Date#<<
      # clamps February 29th onto the 28th).
      def previous_range(key, today:, week_start: "monday")
        case key
        when "week"
          start = Trends.week_start_on_or_before(today, week_start)
          (start - 7)..(start - 1)
        when "days30" then (today - 59)..(today - 30)
        when "year" then Date.new(today.year - 1, 1, 1)..(today << 12)
        end
      end
    end
  end
end
