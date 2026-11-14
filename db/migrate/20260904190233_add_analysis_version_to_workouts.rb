class AddAnalysisVersionToWorkouts < ActiveRecord::Migration[8.1]
  def up
    add_column :workouts, :analysis_version, :integer, default: 1, null: false
    add_check_constraint :workouts, "analysis_version > 0", name: "workouts_analysis_version", validate: false
  end

  def down
    remove_column :workouts, :analysis_version
  end
end
