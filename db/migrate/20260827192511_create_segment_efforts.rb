class CreateSegmentEfforts < ActiveRecord::Migration[8.1]
  def change
    create_table :segment_efforts do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :segment, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: true, index: false
      t.references :sport, null: false, foreign_key: true, index: false

      t.integer :occurrence_index, null: false
      t.datetime :started_at, null: false
      t.integer :elapsed_time, null: false
      t.integer :moving_time, null: false
      t.decimal :distance, precision: 14, scale: 3, null: false
      t.decimal :ascent, precision: 12, scale: 2
      t.decimal :descent, precision: 12, scale: 2
      t.decimal :average_speed, precision: 10, scale: 4, null: false
      t.integer :average_pace
      t.integer :average_heart_rate
      t.integer :max_heart_rate
      t.integer :average_cadence
      t.integer :average_power
      t.integer :max_power
      t.decimal :start_offset_meters, precision: 14, scale: 3, null: false
      t.integer :start_point_index, null: false
      t.integer :end_point_index, null: false
      t.decimal :deviation_meters, precision: 6, scale: 2, null: false
      t.boolean :personal_best, null: false, default: false
      t.boolean :listed, null: false, default: false
      t.boolean :anonymous, null: false, default: false
      t.integer :matcher_version, null: false

      t.timestamps
    end

    add_index :segment_efforts, :uuid, unique: true
    add_index :segment_efforts,
              [ :segment_id, :workout_id, :occurrence_index ],
              unique: true
    add_index :segment_efforts, [ :segment_id, :elapsed_time ]
    add_index :segment_efforts, [ :segment_id, :user_id ], where: "personal_best"
    add_index :segment_efforts, :workout_id
    add_index :segment_efforts, [ :user_id, :segment_id, :elapsed_time ]

    add_check_constraint :segment_efforts,
                         "occurrence_index >= 0",
                         name: "segment_efforts_occurrence_index"
    add_check_constraint :segment_efforts,
                         "elapsed_time > 0",
                         name: "segment_efforts_elapsed_time"
    add_check_constraint :segment_efforts,
                         "moving_time BETWEEN 0 AND elapsed_time",
                         name: "segment_efforts_moving_time"
    add_check_constraint :segment_efforts,
                         "end_point_index > start_point_index",
                         name: "segment_efforts_point_indexes"
    add_check_constraint :segment_efforts,
                         <<~SQL.squish,
                           distance >= 0 AND
                           (ascent IS NULL OR ascent >= 0) AND
                           (descent IS NULL OR descent >= 0) AND
                           average_speed >= 0
                         SQL
                         name: "segment_efforts_non_negative_metrics"
    add_check_constraint :segment_efforts,
                         "start_offset_meters >= 0 AND deviation_meters >= 0",
                         name: "segment_efforts_geometry_metrics"
    add_check_constraint :segment_efforts,
                         <<~SQL.squish,
                           (average_pace IS NULL OR average_pace >= 0) AND
                           (average_heart_rate IS NULL OR average_heart_rate >= 0) AND
                           (max_heart_rate IS NULL OR max_heart_rate >= 0) AND
                           (average_cadence IS NULL OR average_cadence >= 0) AND
                           (average_power IS NULL OR average_power >= 0) AND
                           (max_power IS NULL OR max_power >= 0)
                         SQL
                         name: "segment_efforts_physiological_metrics"
  end
end
