# frozen_string_literal: true

# PLAN_HEART_RATE.md §3.3, histogram version 2: coverage is read against the
# time the device recorded (pauses excluded), frozen strap values are counted
# apart, and a recording whose points are too far apart is marked sparse.
# Version 1 rows read as before (covered = recorded) until the sweep rebuilds
# them.
class AddCoverageDetailsToWorkoutHeartRates < ActiveRecord::Migration[8.1]
  def up
    add_column :workout_heart_rates, :covered_seconds, :integer
    add_column :workout_heart_rates, :frozen_seconds, :integer, null: false, default: 0
    add_column :workout_heart_rates, :sparse, :boolean, null: false, default: false
    execute "UPDATE workout_heart_rates SET covered_seconds = recorded_seconds"
    change_column_null :workout_heart_rates, :covered_seconds, false

    remove_check_constraint :workout_heart_rates, name: "workout_heart_rates_seconds"
    add_check_constraint :workout_heart_rates,
                         "sampled_seconds >= 0 AND recorded_seconds >= 0 AND covered_seconds >= 0 AND frozen_seconds >= 0",
                         name: "workout_heart_rates_seconds"
  end

  def down
    remove_check_constraint :workout_heart_rates, name: "workout_heart_rates_seconds"
    add_check_constraint :workout_heart_rates, "sampled_seconds >= 0 AND recorded_seconds >= 0",
                         name: "workout_heart_rates_seconds"
    remove_column :workout_heart_rates, :sparse
    remove_column :workout_heart_rates, :frozen_seconds
    remove_column :workout_heart_rates, :covered_seconds
  end
end
