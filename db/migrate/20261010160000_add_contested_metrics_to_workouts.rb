# frozen_string_literal: true

# docs/dev/WORKOUT.md: the workout columns an anomaly makes wrong beyond the
# device's ordinary error. Personal records skip a workout for those columns.
class AddContestedMetricsToWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :workouts, :contested_metrics, :string, array: true, default: [], null: false
  end
end
