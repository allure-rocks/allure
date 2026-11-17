# frozen_string_literal: true

module Reactions
  # Batched reaction counts, the viewer's own state and the newest reactors of
  # one page of targets (docs/dev/REACTIONS.md). The feed renders many cards
  # per page, so everything is computed with grouped queries over the page's
  # Workout and RemoteNote rows instead of one query per card. Reaction data is
  # live social state: it never enters a publication snapshot or a remote
  # representation.
  class Summaries
    # The pill's tooltip names at most this many reactors per type
    # (DESIGN.md §10.17); the rest count as other people.
    NAMES_LIMIT = 3

    # The window-ranked position of each reaction inside its (target, type),
    # newest first. The SQL is a frozen pair keyed by target column so no
    # caller input ever reaches the query.
    RANKED_SQL = {
      workout_id: "ROW_NUMBER() OVER (PARTITION BY reactions.workout_id, reactions.kind " \
                  "ORDER BY reactions.created_at DESC, reactions.id DESC) AS position",
      remote_note_id: "ROW_NUMBER() OVER (PARTITION BY reactions.remote_note_id, reactions.kind " \
                      "ORDER BY reactions.created_at DESC, reactions.id DESC) AS position"
    }.freeze

    Summary = Data.define(:counts, :mine, :reactors_by_kind) do
      def count(kind) = counts.fetch(kind.to_s, 0)
      def mine?(kind) = mine == kind.to_s
      def reactors(kind) = reactors_by_kind.fetch(kind.to_s, [])
      def total = counts.values.sum
      def any? = total.positive?
    end

    EMPTY = Summary.new(counts: {}.freeze, mine: nil, reactors_by_kind: {}.freeze)

    # `viewer` is the reading account's actor; `user` the reading account,
    # which may have no actor yet and still reads names.
    def initialize(targets:, viewer: nil, user: nil)
      @targets = Array(targets).compact
      @viewer = viewer
      @user = user || viewer&.user
    end

    def call
      buckets = @targets.index_with do
        { counts: Hash.new(0), mine: nil, reactor_ids: Hash.new { |hash, key| hash[key] = [] } }
      end
      apply_counts!(buckets)
      apply_mine!(buckets)
      apply_reactors!(buckets)
      reactors = load_reactors!(buckets)
      buckets.transform_values do |bucket|
        Summary.new(
          counts: bucket[:counts].freeze,
          mine: bucket[:mine],
          reactors_by_kind: bucket[:reactor_ids].transform_values do |ids|
            ids.filter_map { |id| reactors[id] }.freeze
          end.freeze
        )
      end
    end

    private

    def workouts
      @workouts ||= @targets.select { |target| target.is_a?(Workout) }
    end

    def notes
      @notes ||= @targets.select { |target| target.is_a?(RemoteNote) }
    end

    def apply_counts!(buckets)
      grouped_count(:workout_id, workouts.map(&:id)).each do |(id, kind), count|
        bucket = buckets[workout_index[id]]
        bucket[:counts][kind] += count if bucket
      end
      grouped_count(:remote_note_id, notes.map(&:id)).each do |(id, kind), count|
        bucket = buckets[note_index[id]]
        bucket[:counts][kind] += count if bucket
      end
    end

    def grouped_count(column, ids)
      return {} if ids.empty?

      Reaction.active.where(column => ids).group(column, :kind).count
    end

    def apply_mine!(buckets)
      return unless @viewer

      ids = workouts.map(&:id)
      if ids.any?
        Reaction.active.where(actor: @viewer, workout_id: ids).pluck(:workout_id, :kind).each do |id, kind|
          bucket = buckets[workout_index[id]]
          bucket[:mine] = kind if bucket
        end
      end

      note_ids = notes.map(&:id)
      return if note_ids.empty?

      Reaction.active.where(actor: @viewer, remote_note_id: note_ids).pluck(:remote_note_id, :kind).each do |id, kind|
        bucket = buckets[note_index[id]]
        bucket[:mine] = kind if bucket
      end
    end

    # The newest reactors of each type, one window-ranked query per target type
    # and capped at NAMES_LIMIT per (target, type). On a workout, only the
    # reactions of an audience the viewer may read are named, and the viewer's
    # own (docs/dev/REACTIONS.md): the others still count, unnamed. A deleted
    # account is already gone here; a blocked or deactivated one is dropped
    # once the actors load. A received note is read by its entitled accounts
    # only, so its reactors are named to all of them.
    def apply_reactors!(buckets)
      ranked_reactors(:workout_id, workouts.map(&:id), nameable_on_workouts).each do |id, kind, actor_id|
        bucket = buckets[workout_index[id]]
        bucket[:reactor_ids][kind] << actor_id if bucket
      end
      ranked_reactors(:remote_note_id, notes.map(&:id)).each do |id, kind, actor_id|
        bucket = buckets[note_index[id]]
        bucket[:reactor_ids][kind] << actor_id if bucket
      end
    end

    # The Arel condition naming a workout reaction to the viewer, or nil when
    # nothing can be named.
    def nameable_on_workouts
      table = Reaction.arel_table
      readable = Workouts::ReadableAudiences.new(user: @user, workouts:).call
      conditions = readable.reject { |_id, audiences| audiences.empty? }
        .group_by { |_id, audiences| audiences.sort }
        .map { |audiences, pairs| table[:workout_id].in(pairs.map(&:first)).and(table[:audience].in(audiences)) }
      conditions << table[:actor_id].eq(@viewer.id) if @viewer
      conditions.reduce { |left, right| left.or(right) }
    end

    def ranked_reactors(column, ids, condition = :all)
      return [] if ids.empty? || condition.nil?

      ranked = Reaction.active
        .where(column => ids)
        .joins(:actor)
        .where(actors: { tombstoned_at: nil })
      ranked = ranked.where(condition) unless condition == :all
      ranked = ranked.select(column, :kind, :actor_id, Arel.sql(RANKED_SQL.fetch(column)))
      Reaction.from(ranked, :reactions)
        .where("position <= ?", NAMES_LIMIT)
        .pluck(column, :kind, :actor_id)
    end

    def load_reactors!(buckets)
      ids = buckets.values.flat_map { |bucket| bucket[:reactor_ids].values }.flatten.uniq
      return {} if ids.empty?

      actors = Actor.where(id: ids).includes(:user).index_by(&:id)
      blocked = Federation::Safety::Blocks.blocked_uris(actors.values.map(&:uri))
      actors.reject { |_id, actor| blocked.include?(actor.uri) || actor.user&.deactivated? }
    end

    def workout_index = @workout_index ||= workouts.index_by(&:id)
    def note_index = @note_index ||= notes.index_by(&:id)
  end
end
