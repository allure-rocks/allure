class CreateLaps < ActiveRecord::Migration[8.1]
  def change
    create_table :laps do |t|
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }, index: false

      t.integer :number, null: false
      t.datetime :started_at, null: false
      t.integer :elapsed_time, null: false
      t.integer :moving_time, null: false
      t.decimal :distance, precision: 14, scale: 3
      t.decimal :ascent, precision: 12, scale: 2
      t.decimal :descent, precision: 12, scale: 2
      t.decimal :average_speed, precision: 10, scale: 4
      t.decimal :max_speed, precision: 10, scale: 4
      t.integer :average_pace
      t.integer :average_heart_rate
      t.integer :max_heart_rate
      t.integer :average_cadence
      t.integer :average_power
      t.string :lap_trigger

      t.timestamps
    end

    # Laps are numbered per workout and in order; the composite index also
    # serves the workout foreign key.
    add_index :laps, [ :workout_id, :number ], unique: true

    add_check_constraint :laps,
                          "number >= 1",
                          name: "laps_number"
    add_check_constraint :laps,
                          "elapsed_time >= 0",
                          name: "laps_elapsed_time"
    add_check_constraint :laps,
                          "moving_time BETWEEN 0 AND elapsed_time",
                          name: "laps_moving_time"
    add_check_constraint :laps,
                          <<~SQL.squish,
                            (distance IS NULL OR distance >= 0) AND
                            (ascent IS NULL OR ascent >= 0) AND
                            (descent IS NULL OR descent >= 0) AND
                            (average_speed IS NULL OR average_speed >= 0) AND
                            (max_speed IS NULL OR max_speed >= 0)
                          SQL
                          name: "laps_non_negative_metrics"
    add_check_constraint :laps,
                          <<~SQL.squish,
                            (average_pace IS NULL OR average_pace >= 0) AND
                            (average_heart_rate IS NULL OR average_heart_rate >= 0) AND
                            (max_heart_rate IS NULL OR max_heart_rate >= 0) AND
                            (average_cadence IS NULL OR average_cadence >= 0) AND
                            (average_power IS NULL OR average_power >= 0)
                          SQL
                          name: "laps_physiological_metrics"
  end
end
