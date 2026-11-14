# frozen_string_literal: true

module Allure
  module Stats
    # Training load over days (PLAN_HEART_RATE.md §4): fitness (chronic load)
    # and fatigue (acute load) are exponentially weighted averages of the daily
    # load over 42 and 7 days, both starting at 0 on the first day of history,
    # and form is yesterday's fitness minus yesterday's fatigue — what a
    # session starts the day with. A day without heart rate is a day of zero
    # load. Pure: dates and numbers in, rows out.
    class TrainingLoad
      FITNESS_DAYS = 42
      FATIGUE_DAYS = 7

      Day = Data.define(:date, :load, :fitness, :fatigue, :form)

      attr_reader :days

      # `loads` maps a Date to that day's load; `through` is the last day
      # (today), so the decay of a quiet stretch reaches the present.
      def initialize(loads, through:)
        @days = []
        return if loads.empty?

        fitness = 0.0
        fatigue = 0.0
        (loads.keys.min..through).each do |date|
          load = loads.fetch(date, 0).to_f
          form = fitness - fatigue
          fitness += (load - fitness) / FITNESS_DAYS
          fatigue += (load - fatigue) / FATIGUE_DAYS
          @days << Day.new(date:, load:, fitness:, fatigue:, form:)
        end
      end

      def empty? = @days.empty?

      def last(count) = @days.last(count)

      def today = @days.last
    end
  end
end
