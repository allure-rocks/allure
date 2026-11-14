# frozen_string_literal: true

# PLAN_REMOTE_IMPORTS.md §4: one connection per account and remote provider,
# stable across re-links so the external ids of what it imported keep
# deduplicating. Strava's columns (OAuth state, webhook, rate budget) arrive
# with its own slice.
class CreateImportConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :import_connections do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :provider, null: false
      t.string :status, null: false, default: "unlinked"
      t.text :credentials
      t.string :region, null: false, default: "com"
      t.datetime :token_expires_at
      t.string :external_account_id
      t.string :external_account_name
      t.boolean :auto_sync, null: false, default: true
      t.boolean :sync_equipment, null: false, default: false
      t.references :fallback_sport, foreign_key: { to_table: :sports, on_delete: :nullify }
      t.datetime :last_synced_at
      t.text :last_sync_error
      t.datetime :linked_at
      t.datetime :revoked_at
      t.datetime :pending_expires_at
      t.timestamps
    end

    add_index :import_connections, %i[user_id provider], unique: true
    add_index :import_connections, %i[provider status]
    add_check_constraint :import_connections, "provider IN ('garmin_connect')", name: "import_connections_provider"
    add_check_constraint :import_connections,
                         "status IN ('pending', 'mfa_pending', 'linked', 'expired', 'revoked', 'unlinking', 'unlinked')",
                         name: "import_connections_status"
    add_check_constraint :import_connections, "region IN ('com', 'cn')", name: "import_connections_region"
    add_check_constraint :import_connections,
                         "status NOT IN ('pending', 'mfa_pending') OR pending_expires_at IS NOT NULL",
                         name: "import_connections_pending_expiry"
  end
end
