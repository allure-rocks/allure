class AddElevationEnrichmentToUsersAndWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :elevation_enrichment_enabled, :boolean, null: false, default: false

    add_column :workouts, :elevation_source, :string, null: false, default: "device"
    add_column :workouts, :elevation_source_requested, :string

    add_check_constraint :workouts,
                         "elevation_source IN ('device', 'dem')",
                         name: "workouts_elevation_source"
    add_check_constraint :workouts,
                         "elevation_source_requested IS NULL OR elevation_source_requested IN ('device', 'dem')",
                         name: "workouts_elevation_source_requested"
  end
end
