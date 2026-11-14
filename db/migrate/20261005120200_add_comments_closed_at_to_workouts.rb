# frozen_string_literal: true

# PLAN_COMMENTS.md §5.4: the owner closes and reopens a workout's thread at any
# time. Live state on the workout, never part of a publication snapshot: the
# profile's `comments` setting is the frozen half of the same rule.
class AddCommentsClosedAtToWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :workouts, :comments_closed_at, :datetime
  end
end
