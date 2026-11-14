# frozen_string_literal: true

# M1 locked `import_format` to GPX because GPX was the only parser. FIT
# activity files now produce the same track values, so the constraint widens
# rather than being dropped: the column stays a closed set, and a future
# format must arrive with a migration rather than by accident.
class AllowFitImportFormat < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :workouts, name: "workouts_import_format"
    add_check_constraint :workouts, "import_format IN ('gpx', 'fit')", name: "workouts_import_format"
  end

  def down
    remove_check_constraint :workouts, name: "workouts_import_format"
    add_check_constraint :workouts, "import_format = 'gpx'", name: "workouts_import_format"
  end
end
