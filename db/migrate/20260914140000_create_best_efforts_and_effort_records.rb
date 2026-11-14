# frozen_string_literal: true

class CreateBestEffortsAndEffortRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :best_efforts do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :sport, null: false, foreign_key: true
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }
      t.string :distance_key, null: false
      t.decimal :distance_meters, precision: 14, scale: 3, null: false
      t.integer :duration_seconds, null: false
      t.datetime :started_at, null: false
      t.decimal :start_offset_meters, precision: 14, scale: 3
      t.decimal :end_offset_meters, precision: 14, scale: 3
      t.timestamps
    end
    add_index :best_efforts, %i[workout_id distance_key], unique: true
    add_index :best_efforts, %i[user_id sport_id distance_key duration_seconds],
              name: "index_best_efforts_on_user_sport_distance_duration"
    add_check_constraint :best_efforts, "distance_meters > 0 AND duration_seconds > 0",
                         name: "best_efforts_positive_metrics"
    add_check_constraint :best_efforts,
                         "(start_offset_meters IS NULL OR start_offset_meters >= 0) AND (end_offset_meters IS NULL OR end_offset_meters >= 0)",
                         name: "best_efforts_offsets"
    add_check_constraint :best_efforts,
                         "start_offset_meters IS NULL OR end_offset_meters IS NULL OR end_offset_meters >= start_offset_meters",
                         name: "best_efforts_end_offset"

    create_table :effort_records do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :sport, null: false, foreign_key: true
      t.references :workout, null: true, foreign_key: { on_delete: :nullify }
      t.string :distance_key, null: false
      t.decimal :distance_meters, precision: 14, scale: 3, null: false
      t.integer :duration_seconds, null: false
      t.datetime :workout_started_at, null: false
      t.timestamps
    end
    add_index :effort_records, %i[user_id sport_id distance_key], unique: true
    add_check_constraint :effort_records, "distance_meters > 0 AND duration_seconds > 0",
                         name: "effort_records_positive_metrics"
  end
end
