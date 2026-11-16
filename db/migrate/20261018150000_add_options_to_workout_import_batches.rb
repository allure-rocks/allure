# frozen_string_literal: true

# docs/dev/IMPORT-SOURCES.md: the import page's shared options card. The title
# applies to the single workout a single-file import produces; the commute
# flag and the gear apply to every imported workout of the batch, whose totals
# Workouts::Importer maintains.
class AddOptionsToWorkoutImportBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :workout_import_batches, :title, :string
    add_column :workout_import_batches, :commute, :boolean, default: false, null: false

    create_table :workout_import_batch_equipments, id: false do |t|
      t.bigint :workout_import_batch_id, null: false
      t.bigint :equipment_id, null: false
    end
    add_index :workout_import_batch_equipments, [ :workout_import_batch_id, :equipment_id ],
              unique: true, name: "index_import_batch_equipments_on_batch_and_equipment"
    add_index :workout_import_batch_equipments, [ :equipment_id, :workout_import_batch_id ],
              name: "index_import_batch_equipments_on_equipment_and_batch"
    add_foreign_key :workout_import_batch_equipments, :workout_import_batches, on_delete: :cascade
    add_foreign_key :workout_import_batch_equipments, :equipments, on_delete: :cascade
  end
end
