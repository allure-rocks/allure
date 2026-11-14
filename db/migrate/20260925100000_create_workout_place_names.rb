# frozen_string_literal: true

# One row per recorded place of a workout, derived by Workouts::PlaceNamer from
# the stored toponymy (PLAN_M1.md §11.1). This is the indexable source of the
# owner's place filter and autocomplete, covering every recorded marker rather
# than only the few places a workout displays. Owner-only: never published or
# federated, and never carrying a coordinate.
class CreateWorkoutPlaceNames < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_place_names do |t|
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false, limit: 120
      t.string :kind, null: false, default: ""
      t.integer :position, null: false
      t.timestamps
    end

    add_index :workout_place_names, %i[workout_id position],
              unique: true,
              name: "index_workout_place_names_on_workout_and_position"
    add_index :workout_place_names, %i[user_id name],
              name: "index_workout_place_names_on_user_and_name"
    add_check_constraint :workout_place_names,
                         "position >= 0",
                         name: "workout_place_names_position"
  end
end
