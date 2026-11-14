# frozen_string_literal: true

module HeartRates
  # An account's heart-rate history under its current zones
  # (PLAN_HEART_RATE.md §4): the daily training loads and the time in each
  # zone per week or month. Reads the usable rows of the account's own
  # recordings; a row the rezone job has not reached yet is sliced from its
  # histogram here, so the totals never mix two zone definitions. Days are the
  # account's calendar days. Owner-only.
  class History
    GRANULARITIES = %w[week month].freeze

    Row = Data.define(:date, :sport_id, :zone_seconds, :load)

    def initialize(user:)
      @user = user
      @zones = user.heart_rate_zones
      @time_zone = ActiveSupport::TimeZone[user.time_zone] || Time.zone
    end

    def zones? = !@zones.nil?

    # Whether any of the account's recordings carries usable heart rate,
    # profile or not.
    def any? = scope.exists?

    # Date => load, every usable row of the history.
    def daily_loads
      rows.each_with_object(Hash.new(0.0)) { |row, loads| loads[row.date] += row.load }
    end

    # `[{ period:, seconds: [z1..z5] }]`, oldest first: every period from the
    # one holding `from` to the one holding `through`, zero-filled so a quiet
    # stretch shows as one; empty when none of them holds heart rate.
    def zone_totals(granularity:, from:, through:, sport_id: nil)
      raise ArgumentError, "unknown granularity: #{granularity.inspect}" unless GRANULARITIES.include?(granularity)

      totals = Hash.new { |hash, key| hash[key] = Array.new(Allure::HeartRate::Zones::COUNT, 0) }
      rows.each do |row|
        next if row.date < from || row.date > through
        next if sport_id && row.sport_id != sport_id

        period = period_start(row.date, granularity)
        row.zone_seconds.each_with_index { |seconds, index| totals[period][index] += seconds }
      end
      return [] if totals.empty?

      periods(granularity, from, through).map { |period| { period:, seconds: totals[period] } }
    end

    # Sport id => how many usable recordings fall between `from` and
    # `through`, for the zone page's sport filter.
    def recording_counts(from:, through:)
      rows.each_with_object(Hash.new(0)) do |row, counts|
        counts[row.sport_id] += 1 if row.date.between?(from, through)
      end
    end

    # How many of the account's workouts in the window carry no usable heart
    # rate, so the load can say what it leaves out.
    def workouts_without_heart_rate(from:, to:)
      window = window(from, to)
      window.count - window.joins(:heart_rate).merge(WorkoutHeartRate.usable).count
    end

    # How many usable recordings in the window carry a heart rate over only
    # part of their time: their load counts that part, nothing is imputed.
    def partial_workouts(from:, to:)
      window(from, to).joins(:heart_rate).merge(WorkoutHeartRate.partial).count
    end

    def period_start(date, granularity)
      if granularity == "week"
        Allure::Stats::Trends.week_start_on_or_before(date, @user.week_start)
      else
        date.beginning_of_month
      end
    end

    private

    def window(from, to)
      @user.workouts.where(started_at: @time_zone.local(from.year, from.month, from.day)...(@time_zone.local(to.year, to.month, to.day) + 1.day))
    end

    def periods(granularity, from, through)
      step = granularity == "week" ? ->(date) { date + 7 } : ->(date) { date >> 1 }
      current = period_start(from, granularity)
      last = period_start(through, granularity)
      list = []
      while current <= last
        list << current
        current = step.call(current)
      end
      list
    end

    def rows
      return [] unless @zones

      @rows ||= begin
        fingerprint = @zones.fingerprint
        current = scope.where(zones_fingerprint: fingerprint)
          .pluck("workouts.started_at", "workouts.sport_id", :zone_seconds, :load)
          .map { |started_at, sport_id, seconds, load| Row.new(date: day(started_at), sport_id:, zone_seconds: seconds, load: load.to_f) }
        stale = scope.where.not(zones_fingerprint: fingerprint).or(scope.where(zones_fingerprint: nil))
          .pluck("workouts.started_at", "workouts.sport_id", :histogram)
          .map do |started_at, sport_id, histogram|
            Row.new(date: day(started_at), sport_id:, zone_seconds: @zones.slice(histogram),
                    load: Allure::HeartRate::Load.edwards(histogram, @zones))
          end
        current + stale
      end
    end

    def scope
      WorkoutHeartRate.usable.joins(:workout).where(workouts: { user_id: @user.id })
    end

    def day(time) = time.in_time_zone(@time_zone).to_date
  end
end
