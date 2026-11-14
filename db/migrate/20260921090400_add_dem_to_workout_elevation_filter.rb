# frozen_string_literal: true

# A terrain profile gets its own noise class and ascent threshold
# (PLAN_ELEVATION.md §3): DEM interpolation is smoother than a barometer but
# noisier than a clean barometric trace, and Strava's documented threshold for
# DEM-derived elevation is 10 m. Allure keeps 8 m.
class AddDemToWorkoutElevationFilter < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :workouts, name: "workouts_elevation_filter"
    add_check_constraint :workouts,
                         "elevation_filter IS NULL OR elevation_filter IN ('barometric', 'gps', 'dem')",
                         name: "workouts_elevation_filter"
  end

  def down
    remove_check_constraint :workouts, name: "workouts_elevation_filter"
    add_check_constraint :workouts,
                         "elevation_filter IS NULL OR elevation_filter IN ('barometric', 'gps')",
                         name: "workouts_elevation_filter"
  end
end
