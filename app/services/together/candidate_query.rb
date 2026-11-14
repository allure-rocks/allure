# frozen_string_literal: true

module Together
  # The recordings co-presence detection may compare a workout with
  # (PLAN_TOGETHER.md §8): local accounts with an accepted follow in both
  # directions, both opted in and not suspended; recordings, not commutes,
  # whose recording windows overlap this one's; and whose tracks come near
  # this one's somewhere. The detector makes the decision; this only bounds
  # the pairs it reads.
  class CandidateQuery
    # A recording's window is read from its start and duration; the start
    # bound keeps the query on the start-time index.
    MAX_DURATION = 2.days
    # Two tracks of one outing pass this close at least once.
    NEAR_METERS = 200

    def self.for_workout(workout) = new(workout).call

    # Local accounts this one follows and that follow it back, both accepted,
    # both detecting, neither suspended.
    def self.partner_user_ids(user)
      actor = user.actor
      return [] unless actor && user.together_detection_enabled && !user.deactivated?

      following = Following.accepted_following_of(actor).select(:followed_actor_id)
      followers = Following.accepted_followers_of(actor).select(:follower_actor_id)
      user_ids = Actor.where(local: true, tombstoned_at: nil, id: following).where(id: followers).pluck(:user_id).compact
      User.where(id: user_ids, together_detection_enabled: true, suspended_at: nil, deletion_scheduled_at: nil).where.not(id: user.id).pluck(:id)
    end

    def initialize(workout)
      @workout = workout
    end

    def call
      return Workout.none unless @workout.recording? && @workout.positioned? && !@workout.commute

      partners = self.class.partner_user_ids(@workout.user)
      return Workout.none if partners.empty?

      start = @workout.started_at
      finish = start + @workout.duration
      Workout.recordings
        .where(user_id: partners, commute: false)
        .where(started_at: (start - MAX_DURATION)..finish)
        .ending_at_or_after(start)
        .where(<<~SQL.squish, workout_id: @workout.id, near: NEAR_METERS)
          EXISTS (
            SELECT 1
            FROM track_segments AS candidate_segments
            JOIN track_segments AS own_segments ON own_segments.workout_id = :workout_id
            WHERE candidate_segments.workout_id = workouts.id
              AND ST_DWithin(candidate_segments.geom, own_segments.geom, :near)
          )
        SQL
        .includes(:sport, :user)
        .order(:started_at, :id)
    end
  end
end
