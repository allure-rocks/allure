# frozen_string_literal: true

module Federation
  # Moves this instance's stored identity to a new FEDERATION_BASE_URL: every
  # local URI written under the old base, and every local handle under the
  # old domain, is rewritten to the configured ones. Publication identities
  # keep their uuid, so their links keep working on the new host.
  #
  # Peers are not told: there is no Move, and they keep the old actors, which
  # they have to unfollow and follow again. The `actors_uri_immutable`
  # trigger is lifted inside the transaction only. Read-only unless
  # `apply: true`; a second run changes nothing.
  class HostRename
    class InvalidRename < StandardError; end

    URI_COLUMNS = {
      "workout_publications" => %w[object_uri],
      "segment_publications" => %w[object_uri],
      "comments" => %w[uri activity_uri in_reply_to_uri relay_activity_uri],
      "reactions" => %w[uri],
      "followings" => %w[uri],
      "workout_participations" => %w[wire_activity_uri],
      "federation_outbox_events" => %w[activity_uri object_uri]
    }.freeze
    LOCAL_ACTOR_URI_COLUMNS = %w[uri public_key_id inbox_url shared_inbox_url avatar_url].freeze
    LOCAL_ACTOR_HANDLE_COLUMNS = %w[handle acct].freeze
    JSON_COLUMNS = {
      "federation_outbox_events" => %w[payload],
      "notifications" => %w[payload],
      "webhook_events" => %w[payload]
    }.freeze
    TRIGGER_STATEMENTS = {
      disable: "ALTER TABLE actors DISABLE TRIGGER actors_uri_immutable",
      enable: "ALTER TABLE actors ENABLE TRIGGER actors_uri_immutable"
    }.freeze

    def initialize(from:, to: Allure::Federation.config)
      @from = Allure::Federation::Config.new(base_url: from)
      @to = to
      raise InvalidRename, "FROM is the configured base URL already" if @from.base_url == @to.base_url
    rescue Allure::Federation::Config::InvalidBaseUrl => error
      raise InvalidRename, error.message
    end

    # Rows changed per table, rolled back unless `apply`.
    def call(apply: false)
      counts = {}
      ActiveRecord::Base.transaction do
        toggle_uri_trigger(:disable)
        counts["actors"] = rewrite_local_actors
        URI_COLUMNS.each { |table, columns| counts[table] = rewrite(table, columns.map { uri_assignment(it) }) }
        JSON_COLUMNS.each do |table, columns|
          counts["#{table} (json)"] = rewrite(table, columns.map { json_assignment(it) },
                                              columns.map { "#{it}::text LIKE #{quote("%#{like(old_prefix)}%")}" })
        end
        toggle_uri_trigger(:enable)
        raise ActiveRecord::Rollback unless apply
      end
      counts
    end

    private

    def old_prefix = "#{@from.base_url}/"
    def new_prefix = "#{@to.base_url}/"
    def old_suffix = "@#{@from.domain}"
    def new_suffix = "@#{@to.domain}"

    # The trigger comes from a migration and is not in schema.rb, so a
    # database loaded from the schema has none to lift.
    def toggle_uri_trigger(state)
      present = connection.select_value(
        "SELECT 1 FROM pg_trigger WHERE tgname = 'actors_uri_immutable' AND tgrelid = 'actors'::regclass"
      )
      connection.execute(TRIGGER_STATEMENTS.fetch(state)) if present
    end

    def rewrite_local_actors
      assignments = LOCAL_ACTOR_URI_COLUMNS.map { uri_assignment(it) } +
        LOCAL_ACTOR_HANDLE_COLUMNS.map { handle_assignment(it) }
      rewrite("actors", assignments, [ "uri LIKE #{quote("#{like(old_prefix)}%")}" ], where: "local = TRUE")
    end

    def rewrite(table, assignments, conditions = nil, where: nil)
      conditions ||= assignments.map { |assignment| "#{assignment[/\A\w+/]} LIKE #{quote("#{like(old_prefix)}%")}" }
      filter = "(#{conditions.join(" OR ")})"
      filter = "#{where} AND #{filter}" if where
      connection.update("UPDATE #{connection.quote_table_name(table)} SET #{assignments.join(", ")} WHERE #{filter}")
    end

    def uri_assignment(column)
      "#{column} = CASE WHEN #{column} LIKE #{quote("#{like(old_prefix)}%")} " \
        "THEN #{quote(new_prefix)} || substr(#{column}, #{old_prefix.length + 1}) ELSE #{column} END"
    end

    def handle_assignment(column)
      "#{column} = CASE WHEN #{column} LIKE #{quote("%#{like(old_suffix)}")} " \
        "THEN left(#{column}, -#{old_suffix.length}) || #{quote(new_suffix)} ELSE #{column} END"
    end

    def json_assignment(column)
      "#{column} = replace(replace(#{column}::text, #{quote(old_prefix)}, #{quote(new_prefix)}), " \
        "#{quote("#{old_suffix}\"")}, #{quote("#{new_suffix}\"")})::jsonb"
    end

    def like(value) = ActiveRecord::Base.sanitize_sql_like(value)
    def quote(value) = connection.quote(value)
    def connection = ActiveRecord::Base.connection
  end
end
