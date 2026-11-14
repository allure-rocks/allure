# frozen_string_literal: true

class CreateActors < ActiveRecord::Migration[8.1]
  def change
    create_table :actors do |t|
      t.references :user, null: true, foreign_key: { on_delete: :nullify }, index: false
      t.boolean :local, null: false, default: false
      t.text :uri, null: false
      t.string :handle
      t.string :display_name
      t.text :summary
      t.text :public_key_id
      t.text :public_key_pem
      t.text :private_key_ciphertext
      t.datetime :private_key_retired_at
      t.text :inbox_url
      t.text :shared_inbox_url
      t.string :capability_profile, null: false, default: "unknown"
      t.datetime :last_fetched_at
      t.datetime :tombstoned_at
      t.jsonb :raw

      t.timestamps
    end

    add_index :actors, :uri, unique: true
    add_index :actors, :user_id, unique: true, where: "local = TRUE", name: "index_local_actors_on_user_id"
    add_index :actors, [ :local, :last_fetched_at ], name: "index_actors_on_local_and_last_fetched_at"
    add_index :actors, :tombstoned_at

    add_check_constraint :actors,
                         "local = TRUE OR (user_id IS NULL AND private_key_ciphertext IS NULL)",
                         name: "actors_remote_identity"
    add_check_constraint :actors,
                         "local = FALSE OR user_id IS NOT NULL OR tombstoned_at IS NOT NULL",
                         name: "actors_local_owner"
    add_check_constraint :actors,
                         "capability_profile IN ('unknown', 'public_only', 'restricted_fetch', 'restricted_shared_inbox')",
                         name: "actors_capability_profile"

    execute <<~SQL
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

    execute <<~SQL
      CREATE TRIGGER actors_uri_immutable
      BEFORE UPDATE OF uri ON actors
      FOR EACH ROW
      EXECUTE FUNCTION allure_prevent_actor_uri_change()
    SQL
  end
end
