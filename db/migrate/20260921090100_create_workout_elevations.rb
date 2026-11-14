class CreateWorkoutElevations < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_elevations do |t|
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :status, null: false, default: "pending"
      t.integer :algorithm_version, null: false, default: 1
      t.string :provider
      t.string :dataset
      t.jsonb :samples, null: false, default: []
      t.integer :requests_count, null: false, default: 0
      t.datetime :generated_at
      t.string :last_error
      t.timestamps
    end

    add_check_constraint :workout_elevations,
                         "status IN ('pending', 'ready', 'partial', 'unavailable', 'failed')",
                         name: "workout_elevations_status"
    add_check_constraint :workout_elevations,
                         "algorithm_version > 0",
                         name: "workout_elevations_algorithm_version"
    add_check_constraint :workout_elevations,
                         "requests_count >= 0",
                         name: "workout_elevations_requests_count"
    add_check_constraint :workout_elevations,
                         "jsonb_typeof(samples) = 'array'",
                         name: "workout_elevations_samples"
  end
end
