# frozen_string_literal: true

class CreateWorkoutSegments < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_segments do |t|
      t.references :workout, null: false, foreign_key: true, index: false
      t.integer :position, null: false
      t.datetime :started_at, null: false

      t.integer :duration, null: false
      t.integer :moving_time, null: false
      t.integer :pause_time, null: false
      t.decimal :distance, precision: 14, scale: 3, null: false
      t.decimal :ascent, precision: 12, scale: 2, null: false
      t.decimal :descent, precision: 12, scale: 2, null: false
      t.decimal :min_elevation, precision: 10, scale: 2
      t.decimal :max_elevation, precision: 10, scale: 2
      t.decimal :average_speed, precision: 10, scale: 4, null: false
      t.decimal :max_speed, precision: 10, scale: 4
      t.integer :average_pace
      t.integer :best_pace

      t.integer :average_heart_rate
      t.integer :max_heart_rate
      t.integer :average_cadence
      t.integer :max_cadence
      t.integer :average_power
      t.integer :max_power

      t.line_string :geom, geographic: true, null: false
      t.jsonb :points, null: false
      t.integer :points_count, null: false

      t.timestamps
    end

    add_index :workout_segments, [ :workout_id, :position ], unique: true
    add_index :workout_segments, :geom, using: :gist

    add_check_constraint :workout_segments, "position >= 0", name: "workout_segments_position"
    add_check_constraint :workout_segments, "duration >= 0", name: "workout_segments_duration"
    add_check_constraint :workout_segments,
                         "moving_time >= 0 AND moving_time <= duration",
                         name: "workout_segments_moving_time"
    add_check_constraint :workout_segments,
                         "pause_time = duration - moving_time",
                         name: "workout_segments_pause_time"
    add_check_constraint :workout_segments,
                         "distance >= 0 AND ascent >= 0 AND descent >= 0 AND average_speed >= 0",
                         name: "workout_segments_non_negative_metrics"
    add_check_constraint :workout_segments,
                         "max_speed IS NULL OR max_speed >= 0",
                         name: "workout_segments_max_speed"
    add_check_constraint :workout_segments,
                         "average_pace IS NULL OR average_pace >= 0",
                         name: "workout_segments_average_pace"
    add_check_constraint :workout_segments,
                         "best_pace IS NULL OR best_pace >= 0",
                         name: "workout_segments_best_pace"
    add_check_constraint :workout_segments,
                         <<~SQL.squish,
                           (average_heart_rate IS NULL OR average_heart_rate >= 0)
                           AND (max_heart_rate IS NULL OR max_heart_rate >= 0)
                           AND (average_cadence IS NULL OR average_cadence >= 0)
                           AND (max_cadence IS NULL OR max_cadence >= 0)
                           AND (average_power IS NULL OR average_power >= 0)
                           AND (max_power IS NULL OR max_power >= 0)
                         SQL
                         name: "workout_segments_physiological_metrics"
    add_check_constraint :workout_segments,
                         "points_count >= 2 AND jsonb_typeof(points) = 'array' AND jsonb_array_length(points) = points_count",
                         name: "workout_segments_points"
    add_check_constraint :workout_segments,
                         "ST_NPoints(geom::geometry) >= 2",
                         name: "workout_segments_geometry"
  end
end
