# frozen_string_literal: true

# PLAN_REMOTE_IMPORTS.md §4: workouts and equipment remember the connection
# and the provider's id they came from; import batches and entries learn the
# remote source, its trigger, the quota pause and the `skipped` outcome.
class ExtendImportsForRemoteSources < ActiveRecord::Migration[8.1]
  def change
    %i[workouts equipments].each do |table|
      add_reference table, :import_connection, foreign_key: { on_delete: :nullify }, index: false
      add_column table, :external_id, :string
      add_index table, %i[import_connection_id external_id], unique: true,
                where: "import_connection_id IS NOT NULL AND external_id IS NOT NULL",
                name: "index_#{table}_on_import_connection_external_id"
    end

    change_table :workout_import_batches, bulk: true do |t|
      t.string :source, null: false, default: "file"
      t.references :import_connection, foreign_key: { on_delete: :nullify }
      t.string :trigger, null: false, default: "manual"
      t.date :range_from
      t.date :range_to
      t.datetime :paused_until
      t.datetime :discovered_at
      t.integer :skipped_entries, null: false, default: 0
    end
    change_column_null :workout_import_batches, :sport_id, true
    add_check_constraint :workout_import_batches, "source IN ('file', 'garmin_connect')", name: "workout_import_batches_source"
    add_check_constraint :workout_import_batches, "trigger IN ('manual', 'scheduled', 'webhook')", name: "workout_import_batches_trigger"
    add_check_constraint :workout_import_batches, "source <> 'file' OR sport_id IS NOT NULL", name: "workout_import_batches_file_sport"
    add_check_constraint :workout_import_batches, "range_from IS NULL OR range_to IS NULL OR range_from <= range_to",
                         name: "workout_import_batches_range"
    add_check_constraint :workout_import_batches, "skipped_entries >= 0", name: "workout_import_batches_skipped_entries"

    change_table :workout_import_entries, bulk: true do |t|
      t.string :external_id
      t.jsonb :metadata, null: false, default: {}
      t.string :skip_reason
    end
    add_index :workout_import_entries, %i[batch_id external_id]
    add_check_constraint :workout_import_entries, "jsonb_typeof(metadata) = 'object'", name: "workout_import_entries_metadata_object"
    add_check_constraint :workout_import_entries,
                         "skip_reason IS NULL OR skip_reason IN ('no_geometry', 'unsupported_sport', 'no_file')",
                         name: "workout_import_entries_skip_reason"
    add_check_constraint :workout_import_entries, "(status = 'skipped') = (skip_reason IS NOT NULL)",
                         name: "workout_import_entries_skipped_reason"
    remove_check_constraint :workout_import_entries,
                            "status::text = ANY (ARRAY['queued'::character varying::text, 'processing'::character varying::text, 'imported'::character varying::text, 'failed'::character varying::text, 'duplicate'::character varying::text, 'cancelled'::character varying::text])",
                            name: "workout_import_entries_status"
    add_check_constraint :workout_import_entries,
                         "status IN ('queued', 'processing', 'imported', 'failed', 'duplicate', 'cancelled', 'skipped')",
                         name: "workout_import_entries_status"
  end
end
