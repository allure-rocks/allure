# frozen_string_literal: true

# The workout <-> equipment join rows (`workout_equipments`). Both sides keep
# their HABTM association; this model exists so a bulk equipment change writes
# the join rows in one statement and refreshes the denormalized totals once
# (docs/dev/BULK-ACTIONS.md).
class WorkoutEquipment < ApplicationRecord
  self.table_name = "workout_equipments"

  belongs_to :workout
  belongs_to :equipment
end
