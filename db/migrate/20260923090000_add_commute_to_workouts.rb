# frozen_string_literal: true

# Records whether the owner marked the activity as a commute. Commute is
# orthogonal to the sport: it changes no analysis input, no threshold, and no
# record, only presentation and filtering (docs/dev/WORKOUT.md, docs/dev/FEDERATION.md).
class AddCommuteToWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :workouts, :commute, :boolean, default: false, null: false
  end
end
