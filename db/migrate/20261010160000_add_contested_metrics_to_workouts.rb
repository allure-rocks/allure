# frozen_string_literal: true

# PLAN_M1.md §8.10: the workout columns an anomaly makes wrong beyond the
# device's ordinary error. Personal records skip a workout for those columns.
class AddContestedMetricsToWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :workouts, :contested_metrics, :string, array: true, default: [], null: false
  end
end
