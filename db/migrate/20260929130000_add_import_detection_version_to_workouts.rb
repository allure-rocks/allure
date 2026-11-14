# frozen_string_literal: true

# PLAN_DERIVATIONS.md: the file-derived facts of a workout (recording device,
# re-detectable sport, virtual venue) get their own generation marker, so a
# catalogue change never forces a re-analysis of every stored track.
# Existing rows start at 0 and are reconciled by the next rebuild sweep.
class AddImportDetectionVersionToWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :workouts, :import_detection_version, :integer, default: 0, null: false
    add_check_constraint :workouts, "import_detection_version >= 0", name: "workouts_import_detection_version"
    add_index :workouts, [ :import_detection_version, :id ]
  end
end
