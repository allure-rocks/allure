class CreateWorkoutToponymies < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_toponymies do |t|
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :status, null: false, default: "pending"
      t.integer :algorithm_version, null: false, default: 1
      t.string :provider
      t.jsonb :samples, null: false, default: []
      t.jsonb :start_place, null: false, default: {}
      t.jsonb :finish_place, null: false, default: {}
      t.jsonb :markers, null: false, default: []
      t.integer :sampled_points_count, null: false, default: 0
      t.datetime :generated_at
      t.string :last_error
      t.timestamps
    end

    add_check_constraint :workout_toponymies,
                         "status IN ('pending', 'ready', 'partial', 'unavailable', 'failed')",
                         name: "workout_toponymies_status"
    add_check_constraint :workout_toponymies,
                         "algorithm_version > 0",
                         name: "workout_toponymies_algorithm_version"
    add_check_constraint :workout_toponymies,
                         "sampled_points_count >= 0 AND sampled_points_count <= 40",
                         name: "workout_toponymies_sampled_points_count"
    add_check_constraint :workout_toponymies,
                         "jsonb_typeof(samples) = 'array' AND jsonb_typeof(markers) = 'array'",
                         name: "workout_toponymies_arrays"
    add_check_constraint :workout_toponymies,
                         "jsonb_typeof(start_place) = 'object' AND jsonb_typeof(finish_place) = 'object'",
                         name: "workout_toponymies_places"
  end
end
