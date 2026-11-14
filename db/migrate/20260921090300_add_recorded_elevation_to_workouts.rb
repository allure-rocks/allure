# frozen_string_literal: true

# Records whether the original file carried a valid elevation profile, so the
# UI and the backfill can tell a recorded profile from a DEM-enriched one
# (PLAN_ELEVATION.md §4).
class AddRecordedElevationToWorkouts < ActiveRecord::Migration[8.1]
  def up
    add_column :workouts, :recorded_elevation, :boolean, null: false, default: false
    execute("UPDATE workouts SET recorded_elevation = (min_elevation IS NOT NULL)")
  end

  def down
    remove_column :workouts, :recorded_elevation
  end
end
