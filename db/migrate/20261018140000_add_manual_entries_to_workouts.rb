# frozen_string_literal: true

# PLAN_MANUAL_ENTRY.md §3: a workout the owner typed in by hand, with no file.
# A manual entry has no position, no points, no original file and no remote
# provenance; it carries only the declared figures. The origin check gains the
# value, the recording shape gains its branch, the credit shape lets it through
# with the import origin, and a dedicated shape pins the columns no hand-typed
# entry can fill (they come from a recording's analysis).
class AddManualEntriesToWorkouts < ActiveRecord::Migration[8.1]
  ORIGIN = "origin IN ('import', 'credit', 'manual')"

  RECORDING_SHAPE = <<~SQL.squish
    (origin = 'import' AND points_count IS NOT NULL AND import_format IS NOT NULL
      AND ((start_point IS NULL AND bounds IS NULL) OR (start_point IS NOT NULL AND bounds IS NOT NULL)))
    OR (origin IN ('credit', 'manual') AND start_point IS NULL AND bounds IS NULL
      AND points_count IS NULL AND import_format IS NULL)
  SQL

  CREDIT_SHAPE = <<~SQL.squish
    (origin IN ('import', 'manual') AND credited_from_workout_id IS NULL AND credited_by_actor_id IS NULL
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

  MANUAL_SHAPE = <<~SQL.squish
    origin <> 'manual'
    OR (source_digest IS NULL AND import_connection_id IS NULL AND external_id IS NULL AND source IS NULL
      AND average_cadence IS NULL AND max_cadence IS NULL AND max_power IS NULL
      AND max_speed IS NULL AND best_pace IS NULL AND grade_adjusted_pace IS NULL
      AND min_elevation IS NULL AND max_elevation IS NULL
      AND elevation_filter IS NULL AND elevation_source = 'device' AND elevation_source_requested IS NULL
      AND recorded_elevation = false AND weather_start IS NULL AND weather_end IS NULL
      AND places = '[]'::jsonb AND data_anomalies = '{}'::jsonb AND contested_metrics = '{}')
  SQL

  PREVIOUS_ORIGIN = "origin IN ('import', 'credit')"

  PREVIOUS_RECORDING_SHAPE = <<~SQL.squish
    (origin = 'import' AND points_count IS NOT NULL AND import_format IS NOT NULL
      AND ((start_point IS NULL AND bounds IS NULL) OR (start_point IS NOT NULL AND bounds IS NOT NULL)))
    OR (origin = 'credit' AND start_point IS NULL AND bounds IS NULL
      AND points_count IS NULL AND import_format IS NULL)
  SQL

  PREVIOUS_CREDIT_SHAPE = CREDIT_SHAPE.sub("origin IN ('import', 'manual')", "origin = 'import'")

  def up
    replace_constraints(origin: ORIGIN, recording: RECORDING_SHAPE, credit: CREDIT_SHAPE)
    add_check_constraint :workouts, MANUAL_SHAPE, name: "workouts_manual_shape", validate: false
    validate_check_constraint :workouts, name: "workouts_manual_shape"
  end

  def down
    execute "DELETE FROM workouts WHERE origin = 'manual'"
    remove_check_constraint :workouts, name: "workouts_manual_shape"
    replace_constraints(origin: PREVIOUS_ORIGIN, recording: PREVIOUS_RECORDING_SHAPE, credit: PREVIOUS_CREDIT_SHAPE)
  end

  private

  def replace_constraints(origin:, recording:, credit:)
    { "workouts_origin" => origin, "workouts_recording_shape" => recording, "workouts_credit_shape" => credit }
      .each do |name, expression|
        remove_check_constraint :workouts, name: name
        add_check_constraint :workouts, expression, name: name, validate: false
        validate_check_constraint :workouts, name: name
      end
  end
end
