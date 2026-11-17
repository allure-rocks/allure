# frozen_string_literal: true

# docs/dev/VIRTUAL-PLATFORMS.md: a sport changed by hand is no longer "detected", so the
# re-detection backfill can leave it alone. WorkoutImportEntry::SPORT_SOURCES
# is mirrored by a checked constraint and must be extended in the database too.
class ExtendWorkoutImportEntriesForManualSportChange < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :workout_import_entries, name: "workout_import_entries_sport_source"
    add_check_constraint :workout_import_entries,
                         "sport_source IN ('detected', 'fallback', 'unknown', 'manual')",
                         name: "workout_import_entries_sport_source"
  end

  def down
    remove_check_constraint :workout_import_entries, name: "workout_import_entries_sport_source"
    add_check_constraint :workout_import_entries,
                         "sport_source IN ('detected', 'fallback', 'unknown')",
                         name: "workout_import_entries_sport_source"
  end
end
