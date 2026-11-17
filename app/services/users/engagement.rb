# frozen_string_literal: true

module Users
  # The shared definition of account engagement: activity windows and sessions.
  #
  # Both the administration dashboard and the Prometheus exporter call this, so
  # a "7-day active user" can never mean two different things
  # (docs/dev/METRICS.md). Active users are activity-based (workout or publication), never
  # sign-in-only; connected users hold at least one open session, and a session
  # is open until sign-out, revocation, or expiry (docs/dev/AUTH.md).
  class Engagement
    def initialize(now: Time.current)
      @now = now
    end

    def active_workout(since:)
      Workout.where(created_at: since..@now).distinct.count(:user_id)
    end

    def active_publication(since:)
      WorkoutPublication.where(status: "active", published_at: since..@now)
        .joins(:workout).distinct.count("workouts.user_id")
    end

    def active(since:)
      sql = Workout.sanitize_sql_array([ <<~SQL, since: since, now: @now ])
        SELECT COUNT(DISTINCT user_id) FROM (
          SELECT user_id FROM workouts
            WHERE created_at >= :since AND created_at <= :now
          UNION
          SELECT workouts.user_id FROM workout_publications
            INNER JOIN workouts ON workouts.id = workout_publications.workout_id
            WHERE workout_publications.published_at >= :since AND workout_publications.published_at <= :now
        ) active_users
      SQL
      Workout.connection.select_value(sql).to_i
    end

    def open_sessions = Session.live(@now).count

    def connected = Session.live(@now).distinct.count(:user_id)
  end
end
