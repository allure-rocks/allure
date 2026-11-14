# frozen_string_literal: true

# PLAN_NO_GPS.md §5: a recording whose file carries no usable position (an
# indoor trainer ride, a treadmill run, an erg session, a duration-only
# session) is imported, never rejected for lacking geometry.
#
# The `import` branch of the recording shape loses the requirement that
# `start_point` and `bounds` are present; they are now either both present (a
# positioned recording) or both absent (a positionless one). `points_count` and
# `import_format` stay mandatory for every recording. A `track_segments` row of
# a positionless recording has no `geom`, which becomes nullable.
class ImportPositionlessRecordings < ActiveRecord::Migration[8.1]
  RECORDING_SHAPE = <<~SQL.squish
    (origin = 'import' AND points_count IS NOT NULL AND import_format IS NOT NULL
      AND ((start_point IS NULL AND bounds IS NULL) OR (start_point IS NOT NULL AND bounds IS NOT NULL)))
    OR (origin = 'credit' AND start_point IS NULL AND bounds IS NULL
      AND points_count IS NULL AND import_format IS NULL)
  SQL

  def up
    remove_check_constraint :workouts, name: "workouts_recording_shape"
    add_check_constraint :workouts, RECORDING_SHAPE, name: "workouts_recording_shape", validate: false
    validate_check_constraint :workouts, name: "workouts_recording_shape"

    change_column_null :track_segments, :geom, true
  end

  def down
    execute "DELETE FROM track_segments WHERE geom IS NULL"
    change_column_null :track_segments, :geom, false

    remove_check_constraint :workouts, name: "workouts_recording_shape"
    add_check_constraint :workouts, <<~SQL.squish, name: "workouts_recording_shape", validate: false
      (origin = 'import' AND start_point IS NOT NULL AND bounds IS NOT NULL
        AND points_count IS NOT NULL AND import_format IS NOT NULL)
      OR (origin = 'credit' AND start_point IS NULL AND bounds IS NULL
        AND points_count IS NULL AND import_format IS NULL)
    SQL
    validate_check_constraint :workouts, name: "workouts_recording_shape"
  end
end
