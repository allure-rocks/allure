# frozen_string_literal: true

module Stats
  # Workout aggregates bucketed in SQL. Buckets use the viewer's time zone
  # inside the group key (`AT TIME ZONE` + `date_trunc`); week keys are the
  # actual start-of-week date, Monday- or Sunday-anchored per
  # `users.week_start`. Results are sparse (periods without workouts are
  # absent, never zero-filled) and bounded to the most-recent workouts to cap
  # cost, unless the caller passes `limit: nil` for the unbounded all-time
  # window. No table; pure query. See PLAN_M3.md section 7.6.
  #
  # The period expression is built from Arel nodes (never string
  # interpolation), so even the dynamic time zone cannot become an injection
  # vector. Aggregate selections are static literals.
  class Aggregates
    RECENT_LIMIT = 2000
    GRANULARITIES = %w[day week month year].freeze

    def initialize(user:)
      @user = user
    end

    # `limit` caps the scan to the most recent workouts; nil scans the whole
    # history, which only the all-time window asks for.
    def by_time(granularity:, sport_id: nil, limit: RECENT_LIMIT)
      raise ArgumentError, "unknown granularity: #{granularity.inspect}" unless GRANULARITIES.include?(granularity.to_s)

      period = period_node(granularity.to_s)
      scope = limit ? recent_workouts(limit) : @user.workouts
      scope = scope.where(sport_id:) if sport_id
      rows = scope
        .group(period, :sport_id)
        .order(period, :sport_id)
        .select(
          period.as("period"),
          :sport_id,
          "COUNT(*) AS total_workouts",
          "COALESCE(SUM(distance), 0) AS total_distance",
          "AVG(distance) AS average_distance",
          "COALESCE(SUM(moving_time), 0) AS total_duration",
          "AVG(moving_time) AS average_duration",
          "COALESCE(SUM(ascent), 0) AS total_ascent",
          "AVG(ascent) AS average_ascent",
          "COALESCE(SUM(descent), 0) AS total_descent",
          "AVG(descent) AS average_descent",
          "COALESCE(SUM(calories), 0) AS total_calories",
          "AVG(average_speed) AS average_speed",
          "AVG(average_pace) AS average_pace",
          "(ARRAY_AGG(uuid))[1] AS first_uuid"
        )
      rows.map { |row| serialize_row(row, include_period: true) }
    end

    def by_sport(sport_id: nil)
      scope = recent_workouts
      scope = scope.where(sport_id:) if sport_id
      rows = scope
        .group(:sport_id)
        .order(:sport_id)
        .select(
          :sport_id,
          "COUNT(*) AS total_workouts",
          "COALESCE(SUM(distance), 0) AS total_distance",
          "AVG(distance) AS average_distance",
          "COALESCE(SUM(moving_time), 0) AS total_duration",
          "AVG(moving_time) AS average_duration",
          "COALESCE(SUM(ascent), 0) AS total_ascent",
          "AVG(ascent) AS average_ascent",
          "COALESCE(SUM(descent), 0) AS total_descent",
          "AVG(descent) AS average_descent",
          "COALESCE(SUM(calories), 0) AS total_calories",
          "AVG(average_speed) AS average_speed",
          "AVG(average_pace) AS average_pace"
        )
      rows.map { |row| serialize_row(row, include_period: false) }
    end

    private

    def recent_workouts(limit = RECENT_LIMIT)
      recent = @user.workouts.order(started_at: :desc, id: :desc).limit(limit)
      Workout.from(recent, :workouts)
    end

    # Viewer-timezoned bucket start as an Arel node. `started_at` is stored
    # as naive UTC wall-clock, so convert naive→UTC→zone (a single
    # `AT TIME ZONE` would misread it as zone-local). Sunday weeks shift by
    # a day around a Monday-anchored truncation.
    def period_node(granularity)
      started_at = Workout.arel_table[:started_at]
      as_utc = Arel::Nodes::InfixOperation.new("AT TIME ZONE", started_at, Arel::Nodes.build_quoted("UTC"))
      as_zone = Arel::Nodes::InfixOperation.new("AT TIME ZONE", as_utc, Arel::Nodes.build_quoted(@user.time_zone))
      trunc = ->(unit, expr) { Arel::Nodes::NamedFunction.new("date_trunc", [ Arel::Nodes.build_quoted(unit), expr ]) }

      case granularity
      when "day" then trunc.call("day", as_zone)
      when "week"
        if @user.week_start == "sunday"
          one_day = Arel.sql("'1 day'::interval")
          Arel::Nodes::InfixOperation.new("-",
            trunc.call("week", Arel::Nodes::InfixOperation.new("+", as_zone, one_day)),
            one_day)
        else
          trunc.call("week", as_zone)
        end
      when "month" then trunc.call("month", as_zone)
      when "year" then trunc.call("year", as_zone)
      end
    end

    def serialize_row(row, include_period:)
      serialized = {
        sport_id: row.sport_id,
        total_workouts: row.total_workouts.to_i,
        total_distance: row.total_distance.to_f,
        average_distance: row.average_distance&.to_f,
        total_duration: row.total_duration.to_i,
        average_duration: row.average_duration&.to_f,
        total_ascent: row.total_ascent.to_f,
        average_ascent: row.average_ascent&.to_f,
        total_descent: row.total_descent.to_f,
        average_descent: row.average_descent&.to_f,
        total_calories: row.total_calories.to_i,
        average_speed: row.average_speed&.to_f,
        average_pace: row.average_pace&.to_f
      }
      return serialized unless include_period

      # A bucket holding one workout names it, so a period with a single
      # activity can open that activity rather than a one-row list.
      workout_id = Allure::ShortId.encode(row.first_uuid) if serialized[:total_workouts] == 1 && row.first_uuid
      serialized.merge(period: row.period.to_date, workout_id:)
    end
  end
end
