# frozen_string_literal: true

# The durable ledger behind reviewable bulk operations (PLAN_BULK_ACTIONS.md
# §4): a draft freezes the selection under review, the job walks its items in
# order, and item rows survive the deletion of their workout so the progress
# report can state the outcome.
class CreateWorkoutBulkOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_bulk_operations do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :operation, null: false
      t.string :status, null: false, default: "draft"
      t.jsonb :parameters, null: false, default: {}
      t.datetime :cancellation_requested_at
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :workout_bulk_operations, [ :user_id, :status ]
    add_check_constraint :workout_bulk_operations,
                         "operation::text = ANY (ARRAY['sport_change'::text, 'delete'::text])",
                         name: "workout_bulk_operations_operation"
    add_check_constraint :workout_bulk_operations,
                         "status::text = ANY (ARRAY['draft'::text, 'queued'::text, 'processing'::text, " \
                           "'completed'::text, 'failed'::text, 'cancelled'::text])",
                         name: "workout_bulk_operations_status"

    create_table :workout_bulk_operation_items do |t|
      t.references :workout_bulk_operation, null: false, foreign_key: { on_delete: :cascade },
                                            index: { name: "index_workout_bulk_operation_items_on_operation_id" }
      t.references :workout, null: true, foreign_key: { on_delete: :nullify }
      t.integer :position, null: false, default: 0
      t.string :status, null: false, default: "queued"
      t.string :failure_code
      t.timestamps
    end

    add_index :workout_bulk_operation_items, [ :workout_bulk_operation_id, :position ],
              unique: true, name: "index_workout_bulk_operation_items_on_operation_and_position"
    add_check_constraint :workout_bulk_operation_items, "\"position\" >= 0",
                         name: "workout_bulk_operation_items_position"
    add_check_constraint :workout_bulk_operation_items,
                         "status::text = ANY (ARRAY['queued'::text, 'modified'::text, 'skipped'::text, " \
                           "'failed'::text, 'cancelled'::text])",
                         name: "workout_bulk_operation_items_status"
  end
end
