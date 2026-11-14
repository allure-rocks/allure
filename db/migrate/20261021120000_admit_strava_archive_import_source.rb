# frozen_string_literal: true

# PLAN_STRAVA_ARCHIVE.md §6: a Strava archive is a batch source of its own, and
# the sport its activity type names is recorded as `declared`, which the
# re-detection backfill never overwrites.
class AdmitStravaArchiveImportSource < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :workout_import_batches, name: "workout_import_batches_source"
    add_check_constraint :workout_import_batches, "source IN ('file', 'strava_archive', 'garmin_connect', 'exr')",
                         name: "workout_import_batches_source"

    remove_check_constraint :workout_import_entries, name: "workout_import_entries_sport_source"
    add_check_constraint :workout_import_entries, "sport_source IN ('detected', 'declared', 'fallback', 'unknown', 'manual')",
                         name: "workout_import_entries_sport_source"
  end

  def down
    remove_check_constraint :workout_import_entries, name: "workout_import_entries_sport_source"
    add_check_constraint :workout_import_entries, "sport_source IN ('detected', 'fallback', 'unknown', 'manual')",
                         name: "workout_import_entries_sport_source"

    remove_check_constraint :workout_import_batches, name: "workout_import_batches_source"
    add_check_constraint :workout_import_batches, "source IN ('file', 'garmin_connect', 'exr')",
                         name: "workout_import_batches_source"
  end
end
