# frozen_string_literal: true

class AddSportSourceToWorkoutImportEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :workout_import_entries, :sport_source, :string, null: false, default: "unknown"
    add_check_constraint :workout_import_entries,
                         "sport_source IN ('detected', 'fallback', 'unknown')",
                         name: "workout_import_entries_sport_source"
  end
end
