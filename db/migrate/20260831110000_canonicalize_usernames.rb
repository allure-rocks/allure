# frozen_string_literal: true

class CanonicalizeUsernames < ActiveRecord::Migration[8.1]
  RESERVED_USERNAMES = %w[
    admin administrator root system support help api inbox outbox followers following actor users user
    webfinger nodeinfo well_known oauth allure everyone here all me public federation
  ].freeze

  def up
    assert_no_case_collisions!
    assert_no_reserved_usernames!

    execute <<~SQL
      UPDATE users
      SET username = lower(username)
      WHERE username <> lower(username)
    SQL

    remove_check_constraint :users, name: "users_username_format"
    add_check_constraint :users,
                         "username ~ '\\A[a-z0-9_]{1,30}\\Z'",
                         name: "users_username_format"

    execute <<~SQL
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

    execute <<~SQL
      CREATE TRIGGER users_username_immutable
      BEFORE UPDATE OF username ON users
      FOR EACH ROW
      EXECUTE FUNCTION allure_prevent_username_change()
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS users_username_immutable ON users"
    execute "DROP FUNCTION IF EXISTS allure_prevent_username_change()"

    remove_check_constraint :users, name: "users_username_format"
    add_check_constraint :users,
                         "username ~ '\\A[a-zA-Z0-9_]{1,30}\\Z'",
                         name: "users_username_format"
  end

  private

  def assert_no_case_collisions!
    collision = select_value(<<~SQL)
      SELECT lower(username)
      FROM users
      GROUP BY lower(username)
      HAVING COUNT(*) > 1
      LIMIT 1
    SQL
    return if collision.blank?

    raise ActiveRecord::MigrationError,
          "Cannot canonicalize usernames: case-insensitive collision for #{collision.inspect}"
  end

  def assert_no_reserved_usernames!
    reserved = RESERVED_USERNAMES.map { |username| connection.quote(username) }.join(", ")
    conflict = select_value(<<~SQL)
      SELECT username
      FROM users
      WHERE lower(username) IN (#{reserved})
      LIMIT 1
    SQL
    return if conflict.blank?

    raise ActiveRecord::MigrationError,
          "Cannot canonicalize usernames: reserved username #{conflict.inspect} already exists"
  end
end
