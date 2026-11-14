# frozen_string_literal: true

module People
  # PLAN_PEOPLE.md §3: the only name search the instance offers.
  #
  # It returns a handful of accounts whose username or display name starts with
  # the typed text — discoverable members of this instance, plus the remote
  # accounts the viewer already has a relationship with — and nothing else. A
  # result never carries a biography, place, sport, statistic or activity, and
  # a hidden account is reachable only by its exact handle (the resolve path).
  #
  # Matching is accent-insensitive and prefix-only: a substring search would
  # let a visitor walk the directory from the inside of a name. The local pass
  # folds rows in Ruby because PostgreSQL's `unaccent` is not installed; the
  # scan is bounded, and the page is rate limited.
  class Search
    MIN_QUERY_LENGTH = 3
    LIMIT = 8
    SCAN_LIMIT = 5_000

    # `outgoing` is the viewer's own Follow row toward the result (accepted or
    # pending); `incoming` is the result's pending or accepted Follow toward
    # the viewer. Both are nil when there is no relationship.
    Result = Data.define(:user, :actor, :outgoing, :incoming) do
      def local? = !user.nil?

      def name
        return user.display_name if local?

        actor.display_name.presence || actor.handle.presence || actor.uri
      end

      def handle = local? ? "@#{user.username}" : "@#{actor.acct.presence || actor.handle.presence || actor.uri}"

      # The value the follow service resolves: a bare username locally, the
      # stored `acct` remotely.
      def target = local? ? user.username : (actor.acct.presence || actor.handle)

      def following? = outgoing&.accepted?
      def requested? = outgoing&.pending?
      def follower? = incoming&.accepted?
      def incoming_request? = incoming&.pending?
    end

    def initialize(viewer:, query:, federation_enabled: Allure::Federation::Config.enabled?)
      @viewer = viewer
      @folded_query = fold(query.to_s.strip)
      @federation_enabled = federation_enabled
    end

    def call
      return [] if @folded_query.length < MIN_QUERY_LENGTH

      (local_results + remote_results).first(LIMIT)
    end

    private

    def local_results
      users = User.discoverable.where.not(id: @viewer.id).order(:username).limit(SCAN_LIMIT)
      matched = users.select { |user| matches?(user.username) || matches?(user.display_name) }
      return [] if matched.empty?

      actors = Actor.local.where(user_id: matched.map(&:id)).index_by(&:user_id)
      outgoing, incoming = relationships_for(actors.values)

      matched.map do |user|
        actor = actors[user.id]
        Result.new(user:, actor:, outgoing: actor && outgoing[actor.id], incoming: actor && incoming[actor.id])
      end
    end

    # Only accounts the viewer already follows or is followed by: a remote
    # directory of every actor this instance has ever cached would reveal who
    # else is here.
    def remote_results
      return [] unless @federation_enabled

      local_actor = Actor.local.find_by(user_id: @viewer.id)
      return [] unless local_actor

      outgoing, incoming = relationships_for_actor(local_actor)
      actors = (outgoing.values.map(&:followed_actor) + incoming.values.map(&:follower_actor)).uniq(&:id)
      actors = actors.reject(&:local?)
      actors = actors.reject(&:tombstoned?)
      actors = actors.select { |actor| matches?(actor.acct) || matches?(actor.handle) || matches?(actor.display_name) }
      blocked = Federation::Safety::Blocks.blocked_uris(actors.map(&:uri))
      actors.reject { |actor| blocked.include?(actor.uri) }
            .map { |actor| Result.new(user: nil, actor:, outgoing: outgoing[actor.id], incoming: incoming[actor.id]) }
    end

    def relationships_for(actors)
      ids = actors.map(&:id)
      return [ {}, {} ] if ids.empty?

      local_actor = Actor.local.find_by(user_id: @viewer.id)
      return [ {}, {} ] unless local_actor

      [ outgoing_by(ids, local_actor), incoming_by(ids, local_actor) ]
    end

    def relationships_for_actor(local_actor)
      [ outgoing_by(nil, local_actor), incoming_by(nil, local_actor) ]
    end

    # The viewer's live relationship toward each actor, one query.
    def outgoing_by(ids, local_actor)
      scope = Following.active.where(follower_actor: local_actor)
      scope = scope.where(followed_actor_id: ids) if ids
      scope.order(:id).each_with_object({}) { |following, map| map[following.followed_actor_id] ||= following }
    end

    # The live relationship each actor holds toward the viewer, one query.
    def incoming_by(ids, local_actor)
      scope = Following.active.where(followed_actor: local_actor)
      scope = scope.where(follower_actor_id: ids) if ids
      scope.order(:id).each_with_object({}) { |following, map| map[following.follower_actor_id] ||= following }
    end

    def matches?(value)
      fold(value).start_with?(@folded_query)
    end

    def fold(value) = I18n.transliterate(value.to_s).downcase.strip
  end
end
