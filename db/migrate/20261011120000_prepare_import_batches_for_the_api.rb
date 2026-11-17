# frozen_string_literal: true

# docs/dev/API.md: the REST API names an import batch by a ShortUUID, and
# a batch it creates carries the `api` trigger.
class PrepareImportBatchesForTheApi < ActiveRecord::Migration[8.1]
  def up
    add_column :workout_import_batches, :uuid, :uuid, null: false, default: -> { "gen_random_uuid()" }
    add_index :workout_import_batches, :uuid, unique: true
    remove_check_constraint :workout_import_batches, name: "workout_import_batches_trigger"
    add_check_constraint :workout_import_batches, "trigger IN ('manual', 'scheduled', 'webhook', 'api')",
                         name: "workout_import_batches_trigger"
  end

  def down
    remove_check_constraint :workout_import_batches, name: "workout_import_batches_trigger"
    add_check_constraint :workout_import_batches, "trigger IN ('manual', 'scheduled', 'webhook')",
                         name: "workout_import_batches_trigger"
    remove_index :workout_import_batches, :uuid
    remove_column :workout_import_batches, :uuid
  end
end
