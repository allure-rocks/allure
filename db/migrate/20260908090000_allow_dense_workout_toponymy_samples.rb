class AllowDenseWorkoutToponymySamples < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :workout_toponymies,
                           name: "workout_toponymies_sampled_points_count"
    add_check_constraint :workout_toponymies,
                         "sampled_points_count >= 0",
                         name: "workout_toponymies_sampled_points_count"
  end
end
