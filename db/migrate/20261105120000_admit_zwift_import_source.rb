# frozen_string_literal: true

# docs/dev/REMOTE-IMPORTS.md (slice 7): Zwift joins the remote providers. The
# provider of a connection and the source of a batch are checked lists in the
# database.
class AdmitZwiftImportSource < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :import_connections, name: "import_connections_provider"
    add_check_constraint :import_connections, "provider IN ('garmin_connect', 'exr', 'withings', 'zwift')",
                         name: "import_connections_provider"

    remove_check_constraint :workout_import_batches, name: "workout_import_batches_source"
    add_check_constraint :workout_import_batches,
                         "source IN ('file', 'strava_archive', 'garmin_connect', 'exr', 'withings', 'zwift')",
                         name: "workout_import_batches_source"
  end

  def down
    remove_check_constraint :workout_import_batches, name: "workout_import_batches_source"
    add_check_constraint :workout_import_batches,
                         "source IN ('file', 'strava_archive', 'garmin_connect', 'exr', 'withings')",
                         name: "workout_import_batches_source"

    remove_check_constraint :import_connections, name: "import_connections_provider"
    add_check_constraint :import_connections, "provider IN ('garmin_connect', 'exr', 'withings')",
                         name: "import_connections_provider"
  end
end
