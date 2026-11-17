# frozen_string_literal: true

# docs/dev/SHARED-ACTIVITIES.md: a confirmed credit gives the participant a credit row,
# a workout of their own that carries only the credited metric set and no
# geometry. The location and file columns become nullable for credit rows
# only; the shape checks pin what each origin may and may not hold. The
# existing bounds, points-count and import-format checks already accept NULL.
class AddCreditRowsToWorkouts < ActiveRecord::Migration[8.1]
  RECORDING_SHAPE = <<~SQL.squish
    (origin = 'import' AND start_point IS NOT NULL AND bounds IS NOT NULL
      AND points_count IS NOT NULL AND import_format IS NOT NULL)
    OR (origin = 'credit' AND start_point IS NULL AND bounds IS NULL
      AND points_count IS NULL AND import_format IS NULL)
  SQL

  # A source is set only while attached; deleting the source nullifies it (the
  # detach callback also stamps credit_detached_at, a direct SQL delete leaves
  # it NULL, both read as detached). Every column outside the credited metric
  # set stays empty on a credit row.
  CREDIT_SHAPE = <<~SQL.squish
    (origin = 'import' AND credited_from_workout_id IS NULL AND credited_by_actor_id IS NULL
      AND credit_detached_at IS NULL AND credited_max_climb IS NULL)
    OR (origin = 'credit' AND credited_by_actor_id IS NOT NULL
      AND (credited_from_workout_id IS NULL OR credit_detached_at IS NULL)
      AND source_digest IS NULL AND import_connection_id IS NULL AND external_id IS NULL
      AND source IS NULL AND description IS NULL AND notes IS NULL AND calories IS NULL
      AND average_heart_rate IS NULL AND max_heart_rate IS NULL
      AND average_cadence IS NULL AND max_cadence IS NULL
      AND average_power IS NULL AND max_power IS NULL
      AND grade_adjusted_pace IS NULL AND min_elevation IS NULL AND max_elevation IS NULL
      AND weather_start IS NULL AND weather_end IS NULL
      AND commute = false AND places = '[]'::jsonb AND data_anomalies = '{}'::jsonb)
  SQL

  def up
    add_column :workouts, :origin, :string, null: false, default: "import"
    add_reference :workouts, :credited_from_workout, index: false,
                                                     foreign_key: { to_table: :workouts, on_delete: :nullify }
    add_reference :workouts, :credited_by_actor, foreign_key: { to_table: :actors }
    add_column :workouts, :credit_detached_at, :datetime
    add_column :workouts, :credited_max_climb, :decimal, precision: 12, scale: 2

    change_column_null :workouts, :start_point, true
    change_column_null :workouts, :bounds, true
    change_column_null :workouts, :points_count, true
    change_column_null :workouts, :import_format, true

    add_check_constraint :workouts, "origin IN ('import', 'credit')", name: "workouts_origin", validate: false
    add_check_constraint :workouts, RECORDING_SHAPE, name: "workouts_recording_shape", validate: false
    add_check_constraint :workouts, CREDIT_SHAPE, name: "workouts_credit_shape", validate: false
    validate_check_constraint :workouts, name: "workouts_origin"
    validate_check_constraint :workouts, name: "workouts_recording_shape"
    validate_check_constraint :workouts, name: "workouts_credit_shape"

    # One credit row per participant and source; the source lookup of
    # CreditSyncJob and the detach callback.
    add_index :workouts, %i[credited_from_workout_id user_id],
              unique: true, where: "credited_from_workout_id IS NOT NULL",
              name: "index_workouts_on_live_credit"
    # Re-attachment finds a detached credit of the same owner near a start.
    add_index :workouts, %i[user_id credited_by_actor_id started_at],
              where: "origin = 'credit'", name: "index_workouts_on_credit_reattachment"
  end

  def down
    remove_index :workouts, name: "index_workouts_on_credit_reattachment"
    remove_index :workouts, name: "index_workouts_on_live_credit"
    remove_check_constraint :workouts, name: "workouts_credit_shape"
    remove_check_constraint :workouts, name: "workouts_recording_shape"
    remove_check_constraint :workouts, name: "workouts_origin"
    execute "DELETE FROM workouts WHERE origin = 'credit'"
    change_column_null :workouts, :import_format, false
    change_column_null :workouts, :points_count, false
    change_column_null :workouts, :bounds, false
    change_column_null :workouts, :start_point, false
    remove_column :workouts, :credited_max_climb
    remove_column :workouts, :credit_detached_at
    remove_reference :workouts, :credited_by_actor, foreign_key: { to_table: :actors }
    remove_reference :workouts, :credited_from_workout, foreign_key: { to_table: :workouts }
    remove_column :workouts, :origin
  end
end
