# frozen_string_literal: true

# docs/dev/AI.md: the assistant writes one summary per workout from facts the
# application computed itself. The row keeps the facts it was written from, so
# a regeneration can tell whether they changed and the deferred conversation
# can start there. `workouts.title_source` lets the summary card offer a
# proposed title only where the member has not named the workout themselves.
class AddAssistantSummaries < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :ai_enabled, :boolean, default: false, null: false

    # Existing titles are the members' own as far as the interface is
    # concerned: the default stamps every row "owner", so no historical title
    # is ever proposed for replacement.
    add_column :workouts, :title_source, :string, default: "owner", null: false
    add_check_constraint :workouts, "title_source IN ('default', 'file', 'owner')", name: "workouts_title_source"

    create_table :workout_summaries do |t|
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :status, null: false, default: "pending"
      t.string :locale, null: false
      t.integer :version, null: false, default: 0
      t.jsonb :facts, null: false, default: []
      t.string :facts_digest
      t.string :title
      t.jsonb :sentences, null: false, default: []
      t.string :model
      t.integer :requests_count, null: false, default: 0
      t.datetime :requested_at
      t.datetime :generated_at
      t.string :last_error
      t.timestamps

      t.index %i[status updated_at]
    end
    add_check_constraint :workout_summaries, "status IN ('pending', 'ready', 'failed')",
                         name: "workout_summaries_status"
    add_check_constraint :workout_summaries, "version >= 0", name: "workout_summaries_version"
    add_check_constraint :workout_summaries, "requests_count >= 0", name: "workout_summaries_requests_count"
  end

  def down
    drop_table :workout_summaries
    remove_check_constraint :workouts, name: "workouts_title_source"
    remove_column :workouts, :title_source
    remove_column :users, :ai_enabled
  end
end
