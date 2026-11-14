# frozen_string_literal: true

# Rails' Ruby schema dumper does not represent PostgreSQL triggers. Keep the
# immutable identity guards present when a fresh database is loaded from
# db/schema.rb; normal migrations create the same guards transactionally.
Rails.application.config.after_initialize do
  connection = ActiveRecord::Base.connection
  next unless connection.data_source_exists?("actors")

  connection.transaction do
    connection.execute("SELECT pg_advisory_xact_lock(hashtext('allure_database_invariants'))")

    connection.execute <<~SQL
      CREATE OR REPLACE FUNCTION allure_prevent_username_change()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NEW.username IS DISTINCT FROM OLD.username THEN
          RAISE EXCEPTION 'username is immutable (users_username_immutable)'
            USING ERRCODE = 'check_violation', CONSTRAINT = 'users_username_immutable';
        END IF;
        RETURN NEW;
      END;
      $$
    SQL

    connection.execute <<~SQL
      CREATE OR REPLACE FUNCTION allure_prevent_actor_uri_change()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NEW.uri IS DISTINCT FROM OLD.uri THEN
          RAISE EXCEPTION 'actor URI is immutable (actors_uri_immutable)'
            USING ERRCODE = 'check_violation', CONSTRAINT = 'actors_uri_immutable';
        END IF;
        RETURN NEW;
      END;
      $$
    SQL

    connection.execute <<~SQL
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'users_username_immutable') THEN
          CREATE TRIGGER users_username_immutable
          BEFORE UPDATE OF username ON users
          FOR EACH ROW
          EXECUTE FUNCTION allure_prevent_username_change();
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'actors_uri_immutable') THEN
          CREATE TRIGGER actors_uri_immutable
          BEFORE UPDATE OF uri ON actors
          FOR EACH ROW
          EXECUTE FUNCTION allure_prevent_actor_uri_change();
        END IF;
      END;
      $$
    SQL
  end
rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
  # `db:create` and the first migration boot Rails before the primary database
  # exists. The migration itself installs the guards once the tables exist.
  next
end
