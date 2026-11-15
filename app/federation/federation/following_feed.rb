# frozen_string_literal: true

module Federation
  # The signed-in personal stream: the viewer's own active publications (any
  # audience), local publications from accounts the actor follows, plus remote
  # notes this actor holds an active entitlement for, merged in one
  # chronological order (PLAN_M5 §14.1, DESIGN.md §8.3). A followed local
  # author's followers-only publication always joins the stream, as
  # Workouts::PublicationPolicy serves it to an accepted local follower. With `include_public:`, the instance's remaining public publications
  # join the stream, deduplicated against followed authors and the viewer's own
  # actor.
  #
  # A workout appears once: among its publications the viewer may read, the
  # narrowest audience is the one shown (docs/dev/PUBLISHING.md).
  #
  # The union is a projection of identities only; the records themselves are
  # hydrated in two batched queries so the page never builds one query per row
  # and the remote side never crosses another account's entitlements.
  class FollowingFeed
    # `publication` is the local item's publication shown; nil for a remote
    # note.
    Item = Data.define(:kind, :record, :published_at, :publication) do
      def initialize(kind:, record:, published_at:, publication: nil) = super
    end

    # An account in its deletion window is deactivated: its publications are
    # hidden locally until the purge withdraws them (PLAN_ACCOUNT.md §4.2),
    # exactly as WorkoutPublication.of_available_owners reads it. The union is
    # raw SQL, so the rule is spelled here for every local fragment.
    OWNER_AVAILABLE = <<~SQL.squish
      workout_publications.actor_id NOT IN (
        SELECT actors.id
        FROM actors
        INNER JOIN users ON users.id = actors.user_id
        WHERE users.deletion_scheduled_at IS NOT NULL
      )
    SQL

    LOCAL_FOLLOWED_SQL = <<~SQL.squish
      SELECT 'local' AS kind,
             workout_publications.id AS id,
             workout_publications.published_at AS published_at
      FROM workout_publications
      INNER JOIN followings
        ON followings.followed_actor_id = workout_publications.actor_id
       AND followings.status = 'accepted'
       AND followings.follower_actor_id = ?
      INNER JOIN actors
        ON actors.id = workout_publications.actor_id
       AND actors.tombstoned_at IS NULL
      WHERE workout_publications.status = 'active'
        AND #{OWNER_AVAILABLE}
        AND workout_publications.audience IN ('public', 'followers')
    SQL

    REMOTE_SQL = <<~SQL.squish
      SELECT 'remote' AS kind,
             remote_notes.id AS id,
             COALESCE(remote_notes.published_at, remote_notes.received_at) AS published_at
      FROM remote_notes
      INNER JOIN remote_note_recipients
        ON remote_note_recipients.remote_note_id = remote_notes.id
       AND remote_note_recipients.status = 'active'
       AND remote_note_recipients.recipient_actor_id = ?
      INNER JOIN actors
        ON actors.id = remote_notes.actor_id
       AND actors.tombstoned_at IS NULL
      WHERE remote_notes.status = 'active'
    SQL

    # The viewer's own active publications, whatever the audience: the owner
    # always sees what they published, with or without the Public switch.
    OWN_SQL = <<~SQL.squish
      SELECT 'local' AS kind,
             workout_publications.id AS id,
             workout_publications.published_at AS published_at
      FROM workout_publications
      INNER JOIN actors
        ON actors.id = workout_publications.actor_id
       AND actors.tombstoned_at IS NULL
      WHERE workout_publications.status = 'active'
        AND workout_publications.actor_id = ?
        AND #{OWNER_AVAILABLE}
    SQL

    # Instance-public publications whose author is neither followed nor the
    # viewer, so an author never appears twice with "Public" on.
    PUBLIC_SQL = <<~SQL.squish
      SELECT 'local' AS kind,
             workout_publications.id AS id,
             workout_publications.published_at AS published_at
      FROM workout_publications
      INNER JOIN actors
        ON actors.id = workout_publications.actor_id
       AND actors.tombstoned_at IS NULL
      WHERE workout_publications.status = 'active'
        AND workout_publications.audience = 'public'
        AND workout_publications.actor_id <> ?
        AND #{OWNER_AVAILABLE}
        AND NOT EXISTS (
          SELECT 1
          FROM followings
          WHERE followings.follower_actor_id = ?
            AND followings.followed_actor_id = workout_publications.actor_id
            AND followings.status = 'accepted'
        )
    SQL

    ORDER_SQL = "ORDER BY published_at DESC, kind DESC, id DESC"

    def initialize(actor:, include_public: false)
      @actor = actor
      @include_public = include_public
    end

    def relation
      WorkoutPublication
        .from(Arel.sql("(#{sql}) AS following_feed_items"))
        .select("following_feed_items.kind", "following_feed_items.id", "following_feed_items.published_at")
    end

    def items_for(rows)
      rows = rows.to_a
      publications = load_publications(rows.select { |row| row.kind == "local" }.map(&:id))
      notes = load_notes(rows.select { |row| row.kind == "remote" }.map(&:id))

      rows.map do |row|
        if row.kind == "local"
          publication = publications[row.id]
          Item.new(kind: row.kind, record: publication&.workout, published_at: row.published_at, publication:)
        else
          Item.new(kind: row.kind, record: notes[row.id], published_at: row.published_at)
        end
      end
    end

    def follows_anyone?
      Following.accepted_following_of(@actor).exists?
    end

    private

    def sql
      @sql ||= begin
        fragments = [ LOCAL_FOLLOWED_SQL, OWN_SQL ]
        parameters = [ @actor.id, @actor.id ]
        if @include_public
          fragments << PUBLIC_SQL
          parameters << @actor.id << @actor.id
        end
        parameters << @actor.id

        WorkoutPublication.sanitize_sql_array(
          [ "#{one_per_workout(fragments.join(' UNION ALL '))} UNION ALL #{REMOTE_SQL} #{ORDER_SQL}", *parameters ]
        )
      end
    end

    # Keeps, per workout, the narrowest of the candidate publications.
    def one_per_workout(candidates)
      <<~SQL.squish
        SELECT local_items.kind, local_items.id, local_items.published_at FROM (
          SELECT DISTINCT ON (workout_publications.workout_id)
                 'local' AS kind,
                 workout_publications.id AS id,
                 workout_publications.published_at AS published_at
          FROM workout_publications
          WHERE workout_publications.id IN (SELECT local_candidates.id FROM (#{candidates}) AS local_candidates)
          ORDER BY workout_publications.workout_id, #{WorkoutPublication::AUDIENCE_RANK_SQL}, workout_publications.id
        ) AS local_items
      SQL
    end

    def load_publications(publication_ids)
      return {} if publication_ids.empty?

      user_associations = %i[avatar_attachment gravatar_cache_attachment]
      actor_association = :user
      if Allure::Funding.enabled?
        user_associations << :active_funding_contributions
        actor_association = { user: :active_funding_contributions }
      end

      WorkoutPublication
        .where(id: publication_ids)
        .includes({ route_image_attachment: :blob }, { actor: actor_association },
                  workout: [ :sport, { user: user_associations } ])
        .each_with_object({}) do |publication, map|
          map[publication.id] = publication if publication.workout
        end
    end

    def load_notes(note_ids)
      return {} if note_ids.empty?

      RemoteNote.where(id: note_ids).includes({ actor: :avatar_cache_attachment }, attachments: :blob).index_by(&:id)
    end
  end
end
