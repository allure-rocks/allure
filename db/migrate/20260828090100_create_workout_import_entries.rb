# frozen_string_literal: true

class CreateWorkoutImportEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_import_entries do |t|
      t.references :batch, null: false, foreign_key: { to_table: :workout_import_batches }
      t.references :workout, foreign_key: true
      t.integer :position, null: false
      t.string :source_key, null: false
      t.string :source_name, null: false
      t.string :source_path
      t.string :status, null: false, default: "queued"
      t.string :source_digest, limit: 64
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :workout_import_entries, [ :batch_id, :source_key ], unique: true
    add_index :workout_import_entries, [ :batch_id, :position ], unique: true
    add_index :workout_import_entries, :source_digest
    add_check_constraint :workout_import_entries, "position >= 0", name: "workout_import_entries_position"
    add_check_constraint :workout_import_entries,
                         "status IN ('queued', 'processing', 'imported', 'failed', 'duplicate', 'cancelled')",
                         name: "workout_import_entries_status"
  end
end
