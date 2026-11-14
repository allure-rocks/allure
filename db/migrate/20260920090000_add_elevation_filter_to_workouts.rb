# frozen_string_literal: true

# Detected elevation noise class of the source recording (PLAN_M1.md section
# 8.6). It selects the ascent threshold: `barometric` counts small rolls with a
# light filter (1 m), `gps` needs the heavier filter and a noise-clearing
# change (3 m). Null when the sport does not record elevation.
class AddElevationFilterToWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :workouts, :elevation_filter, :string
    add_check_constraint :workouts,
                         "elevation_filter IS NULL OR elevation_filter IN ('barometric', 'gps')",
                         name: "workouts_elevation_filter"
  end
end
