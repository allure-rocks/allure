class AllowKmlImportFormat < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :workouts, name: "workouts_import_format"
    add_check_constraint :workouts, "import_format IN ('gpx', 'fit', 'tcx', 'kml')", name: "workouts_import_format"
  end

  def down
    remove_check_constraint :workouts, name: "workouts_import_format"
    add_check_constraint :workouts, "import_format IN ('gpx', 'fit', 'tcx')", name: "workouts_import_format"
  end
end
