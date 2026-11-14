# frozen_string_literal: true

class CreateWorkoutImportBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_import_batches do |t|
      t.references :user, null: false, foreign_key: true
      t.references :sport, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.string :workout_visibility, null: false, default: "private"
      t.string :analysis_visibility, null: false, default: "private"
      t.string :map_visibility, null: false, default: "private"
      t.string :media_visibility, null: false, default: "private"
      t.text :notes
      t.integer :total_entries, null: false, default: 0
      t.integer :processed_entries, null: false, default: 0
      t.integer :imported_entries, null: false, default: 0
      t.integer :failed_entries, null: false, default: 0
      t.integer :duplicate_entries, null: false, default: 0
      t.integer :cancelled_entries, null: false, default: 0
      t.datetime :cancellation_requested_at
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.timestamps
    end

    add_index :workout_import_batches, [ :user_id, :created_at ]
    add_check_constraint :workout_import_batches,
                         "status IN ('queued', 'processing', 'completed', 'failed', 'cancelled')",
                         name: "workout_import_batches_status"
    %i[total_entries processed_entries imported_entries failed_entries duplicate_entries cancelled_entries].each do |column|
      add_check_constraint :workout_import_batches, "#{column} >= 0", name: "workout_import_batches_#{column}"
    end
    %i[workout_visibility analysis_visibility map_visibility media_visibility].each do |column|
      add_check_constraint :workout_import_batches,
                           "#{column} IN ('public', 'followers_only', 'private')",
                           name: "workout_import_batches_#{column}"
    end
  end
end
