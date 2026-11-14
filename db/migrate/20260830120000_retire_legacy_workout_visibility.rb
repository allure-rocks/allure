# frozen_string_literal: true

class RetireLegacyWorkoutVisibility < ActiveRecord::Migration[8.1]
  def up
    # Do not leave queued jobs depending on columns removed by this migration.
    execute <<~SQL
      UPDATE workout_import_batches
      SET status = 'cancelled',
          cancellation_requested_at = COALESCE(cancellation_requested_at, CURRENT_TIMESTAMP),
          completed_at = COALESCE(completed_at, CURRENT_TIMESTAMP),
          error_message = COALESCE(error_message, 'Cancelled during the publishing model migration')
      WHERE status IN ('queued', 'processing')
    SQL

    %w[
      workouts_workout_visibility
      workouts_analysis_visibility
      workouts_map_visibility
      workouts_media_visibility
      workouts_federation_state
    ].each { |name| remove_check_constraint :workouts, name: name }
    remove_index :workouts, name: "index_workouts_on_workout_visibility_and_started_at"
    remove_columns :workouts,
                   :workout_visibility,
                   :analysis_visibility,
                   :map_visibility,
                   :media_visibility,
                   :federation_state,
                   :published_at

    %w[
      workout_import_batches_workout_visibility
      workout_import_batches_analysis_visibility
      workout_import_batches_map_visibility
      workout_import_batches_media_visibility
    ].each { |name| remove_check_constraint :workout_import_batches, name: name }
    remove_columns :workout_import_batches,
                   :workout_visibility,
                   :analysis_visibility,
                   :map_visibility,
                   :media_visibility
  end

  def down
    add_column :workouts, :workout_visibility, :string, null: false, default: "private"
    add_column :workouts, :analysis_visibility, :string, null: false, default: "private"
    add_column :workouts, :map_visibility, :string, null: false, default: "private"
    add_column :workouts, :media_visibility, :string, null: false, default: "private"
    add_column :workouts, :federation_state, :string, null: false, default: "draft"
    add_column :workouts, :published_at, :datetime
    add_index :workouts, [ :workout_visibility, :started_at ], order: { started_at: :desc }
    add_check_constraints(:workouts)

    add_column :workout_import_batches, :workout_visibility, :string, null: false, default: "private"
    add_column :workout_import_batches, :analysis_visibility, :string, null: false, default: "private"
    add_column :workout_import_batches, :map_visibility, :string, null: false, default: "private"
    add_column :workout_import_batches, :media_visibility, :string, null: false, default: "private"
    add_batch_check_constraints
  end

  private

  def add_check_constraints(table)
    add_check_constraint table, "workout_visibility IN ('public', 'followers_only', 'private')", name: "workouts_workout_visibility"
    add_check_constraint table, "analysis_visibility IN ('public', 'followers_only', 'private')", name: "workouts_analysis_visibility"
    add_check_constraint table, "map_visibility IN ('public', 'followers_only', 'private')", name: "workouts_map_visibility"
    add_check_constraint table, "media_visibility IN ('public', 'followers_only', 'private')", name: "workouts_media_visibility"
    add_check_constraint table, "federation_state IN ('draft', 'local_only', 'published', 'federated', 'suppress')", name: "workouts_federation_state"
  end

  def add_batch_check_constraints
    add_check_constraint :workout_import_batches, "workout_visibility IN ('public', 'followers_only', 'private')", name: "workout_import_batches_workout_visibility"
    add_check_constraint :workout_import_batches, "analysis_visibility IN ('public', 'followers_only', 'private')", name: "workout_import_batches_analysis_visibility"
    add_check_constraint :workout_import_batches, "map_visibility IN ('public', 'followers_only', 'private')", name: "workout_import_batches_map_visibility"
    add_check_constraint :workout_import_batches, "media_visibility IN ('public', 'followers_only', 'private')", name: "workout_import_batches_media_visibility"
  end
end
