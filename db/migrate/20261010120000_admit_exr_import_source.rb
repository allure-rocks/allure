# frozen_string_literal: true

# PLAN_REMOTE_IMPORTS.md §7b: EXR joins the remote providers. The provider of a
# connection and the source of a batch are checked lists in the database.
class AdmitExrImportSource < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :import_connections, name: "import_connections_provider"
    add_check_constraint :import_connections, "provider IN ('garmin_connect', 'exr')", name: "import_connections_provider"

    remove_check_constraint :workout_import_batches, name: "workout_import_batches_source"
    add_check_constraint :workout_import_batches, "source IN ('file', 'garmin_connect', 'exr')",
                         name: "workout_import_batches_source"
  end

  def down
    remove_check_constraint :workout_import_batches, name: "workout_import_batches_source"
    add_check_constraint :workout_import_batches, "source IN ('file', 'garmin_connect')", name: "workout_import_batches_source"

    remove_check_constraint :import_connections, name: "import_connections_provider"
    add_check_constraint :import_connections, "provider = 'garmin_connect'", name: "import_connections_provider"
  end
end
