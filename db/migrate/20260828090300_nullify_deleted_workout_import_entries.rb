# frozen_string_literal: true

class NullifyDeletedWorkoutImportEntries < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :workout_import_entries, :workouts
    add_foreign_key :workout_import_entries, :workouts, on_delete: :nullify
  end
end
