# frozen_string_literal: true

module People
  # PLAN_PEOPLE.md §4: accounts worth following, each with the reason it is
  # offered. Every signal comes from something the viewer can already see, so
  # a suggestion never reveals a relationship or a place:
  #
  # - `together`: an outing the instance detected as done together;
  # - `interaction`: a reaction or a comment on one of the viewer's workouts;
  # - `leaderboard`: another athlete on a course the viewer has ridden.
  #
  # A suggestion never returns the viewer, an account already followed or
  # invited, a dismissed account, a blocked actor, or a local account that is
  # not discoverable.
  class Suggestions
    LIMIT = 5
    WINDOW = 90.days
    LEADERBOARD_WINDOW = 180.days
    LEADERBOARD_CANDIDATES = 10

    Suggestion = Data.define(:actor, :user, :reason) do
      def local? = !user.nil?
      def name = local? ? user.display_name : (actor.display_name.presence || actor.handle.presence || actor.uri)
      def handle = local? ? "@#{user.username}" : "@#{actor.acct.presence || actor.handle.presence || actor.uri}"
      def target = local? ? user.username : (actor.acct.presence || actor.handle)
    end

    def initialize(viewer:, now: Time.current)
      @viewer = viewer
      @now = now
    end

    def call
      @local_actor = Actor.local.find_by(user_id: @viewer.id)
      @followed_ids = followed_actor_ids
      @dismissed_ids = PeopleSuggestionDismissal.where(user: @viewer).pluck(:actor_id).to_set

      groups = [
        [ together_candidates, :together ],
        [ interaction_candidates, :interaction ],
        [ leaderboard_candidates, :leaderboard ]
      ]
      candidates = groups.flat_map(&:first).compact.uniq(&:id)
      # One batch instead of two queries per candidate.
      @blocked_uris = Federation::Safety::Blocks.blocked_uris(candidates.map(&:uri))

      @seen = Set.new
      @results = []
      groups.each { |actors, reason| actors.each { |actor| add(actor, reason) } }
      @results.first(LIMIT)
    end

    private

    def add(actor, reason)
      return if actor.nil? || @seen.include?(actor.id)
      return unless eligible?(actor)

      @seen << actor.id
      @results << Suggestion.new(actor:, user: actor.local? ? actor.user : nil, reason:)
    end

    def eligible?(actor)
      return false if actor.user_id == @viewer.id
      return false if actor.id == @local_actor&.id
      return false if @followed_ids.include?(actor.id)
      return false if @dismissed_ids.include?(actor.id)
      return false if actor.tombstoned?
      return false if @blocked_uris.include?(actor.uri)
      # A local account that has not opted into discovery is never suggested.
      return false if actor.local? && !actor.user&.discoverable?

      true
    end

    def followed_actor_ids
      return Set.new unless @local_actor

      Following.active.where(follower_actor: @local_actor).pluck(:followed_actor_id).to_set
    end

    # An outing the instance detected as done together, newest first.
    def together_candidates
      return [] unless @local_actor

      ids = WorkoutParticipation
        .active
        .where(workout_id: @viewer.workouts.select(:id), origin: "detection")
        .where(created_at: @now - WINDOW..)
        .where.not(participant_actor_id: @local_actor.id)
        .order(created_at: :desc)
        .limit(20)
        .pluck(:participant_actor_id)
      actors_by_id(ids)
    end

    # Reactions and comments on the viewer's workouts, newest first, folded
    # into one recency order.
    def interaction_candidates
      workout_ids = @viewer.workouts.select(:id)
      since = @now - WINDOW
      ids = Reaction.active.where(workout_id: workout_ids, created_at: since..)
                     .order(created_at: :desc).limit(20).pluck(:actor_id) +
        Comment.where(workout_id: workout_ids, status: "active", created_at: since..)
               .order(created_at: :desc).limit(20).pluck(:actor_id)
      actors_by_id(ids.uniq)
    end

    # Athletes who share a course with the viewer, most shared courses first.
    def leaderboard_candidates
      segment_ids = @viewer.segment_efforts
        .where(started_at: @now - LEADERBOARD_WINDOW..)
        .distinct.pluck(:segment_id)
      return [] if segment_ids.empty?

      counts = SegmentEffort
        .where(segment_id: segment_ids, started_at: @now - LEADERBOARD_WINDOW..)
        .where.not(user_id: @viewer.id)
        .group(:user_id)
        .order(Arel.sql("COUNT(*) DESC"), :user_id)
        .limit(LEADERBOARD_CANDIDATES)
        .count
      actors_by_user_ids(counts.keys)
    end

    def actors_by_id(ids)
      return [] if ids.empty?

      actors = Actor.where(id: ids).index_by(&:id)
      ids.filter_map { |id| actors[id] }
    end

    def actors_by_user_ids(user_ids)
      return [] if user_ids.empty?

      actors = Actor.local.where(user_id: user_ids).index_by(&:user_id)
      user_ids.filter_map { |id| actors[id] }
    end
  end
end
