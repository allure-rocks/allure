# frozen_string_literal: true

# A demo instance dates its seeded recordings near the present instead of the
# day the file was recorded (PLAN_DEMO.md §4). The offset in seconds is stored
# on the workout so every re-analysis of the immutable original re-applies it
# through Workouts::OriginalTrack and never falls back to the file's own
# dates. Every ordinary import keeps the default zero.
class AddTimeShiftSecondsToWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :workouts, :time_shift_seconds, :bigint, default: 0, null: false
  end
end
