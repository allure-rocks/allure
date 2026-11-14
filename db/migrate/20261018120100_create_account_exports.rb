class CreateAccountExports < ActiveRecord::Migration[8.1]
  def change
    create_table :account_exports do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :status, null: false, default: "pending"
      t.bigint :byte_size
      t.jsonb :counts, null: false, default: {}
      t.string :error_code
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :expires_at
      t.timestamps
    end
    add_index :account_exports, :uuid, unique: true
    add_index :account_exports, :user_id, unique: true, where: "status IN ('pending', 'running')",
                                          name: "index_account_exports_one_in_progress"
    add_index :account_exports, %i[status expires_at]
    add_check_constraint :account_exports,
                         "status IN ('pending', 'running', 'ready', 'failed', 'expired')",
                         name: "account_exports_status"
    add_check_constraint :account_exports,
                         "status <> 'ready' OR (expires_at IS NOT NULL AND completed_at IS NOT NULL)",
                         name: "account_exports_ready"
  end
end
