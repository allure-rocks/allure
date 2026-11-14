class CreateDetectedLaps < ActiveRecord::Migration[8.1]
  def change
    create_table :detected_laps do |t|
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :segment_effort, foreign_key: { on_delete: :nullify }, index: false

      t.string :source, null: false
      t.integer :number, null: false
      t.integer :start_point_index, null: false
      t.integer :end_point_index, null: false
      t.decimal :start_distance, precision: 14, scale: 3, null: false
      t.decimal :end_distance, precision: 14, scale: 3, null: false
      t.datetime :started_at, null: false
      t.integer :elapsed_time, null: false
      t.integer :moving_time, null: false
      t.decimal :distance, precision: 14, scale: 3, null: false
      t.decimal :ascent, precision: 12, scale: 2
      t.decimal :descent, precision: 12, scale: 2
      t.decimal :average_speed, precision: 10, scale: 4
      t.integer :average_pace
      t.decimal :max_speed, precision: 10, scale: 4
      t.integer :average_heart_rate
      t.integer :max_heart_rate
      t.integer :average_cadence
      t.integer :average_power
      t.decimal :average_grade, precision: 5, scale: 2
      t.decimal :max_grade, precision: 5, scale: 2
      t.decimal :climb_score, precision: 14, scale: 2
      t.integer :detector_version, null: false
      t.string :name

      t.timestamps
    end

    add_index :detected_laps, [ :workout_id, :source, :number ], unique: true
    add_index :detected_laps, [ :workout_id, :start_distance ]
    add_index :detected_laps, :segment_effort_id

    add_check_constraint :detected_laps,
                         "source IN ('loop', 'route', 'pause', 'climb')",
                         name: "detected_laps_source"
    add_check_constraint :detected_laps, "number >= 1", name: "detected_laps_number"
    add_check_constraint :detected_laps,
                         "end_point_index > start_point_index",
                         name: "detected_laps_point_indexes"
    add_check_constraint :detected_laps,
                         "end_distance >= start_distance",
                         name: "detected_laps_distances"
    add_check_constraint :detected_laps, "elapsed_time > 0", name: "detected_laps_elapsed_time"
    add_check_constraint :detected_laps,
                         "moving_time BETWEEN 0 AND elapsed_time",
                         name: "detected_laps_moving_time"
    add_check_constraint :detected_laps,
                         <<~SQL.squish,
                           distance > 0 AND
                           (ascent IS NULL OR ascent >= 0) AND
                           (descent IS NULL OR descent >= 0) AND
                           (average_speed IS NULL OR average_speed >= 0) AND
                           (max_speed IS NULL OR max_speed >= 0)
                         SQL
                         name: "detected_laps_non_negative_metrics"
    add_check_constraint :detected_laps,
                         <<~SQL.squish,
                           (average_pace IS NULL OR average_pace >= 0) AND
                           (average_heart_rate IS NULL OR average_heart_rate >= 0) AND
                           (max_heart_rate IS NULL OR max_heart_rate >= 0) AND
                           (average_cadence IS NULL OR average_cadence >= 0) AND
                           (average_power IS NULL OR average_power >= 0)
                         SQL
                         name: "detected_laps_physiological_metrics"
    add_check_constraint :detected_laps,
                         <<~SQL.squish,
                           (average_grade IS NULL OR average_grade >= 0) AND
                           (max_grade IS NULL OR max_grade >= 0) AND
                           (climb_score IS NULL OR climb_score >= 0)
                         SQL
                         name: "detected_laps_climb_metrics"
    add_check_constraint :detected_laps,
                         "detector_version > 0",
                         name: "detected_laps_detector_version"
    add_check_constraint :detected_laps,
                         "name IS NULL OR char_length(name) <= 120",
                         name: "detected_laps_name_length"
  end
end
