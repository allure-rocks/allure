# frozen_string_literal: true

# docs/dev/SHARED-ACTIVITIES.md: each account may opt out of co-presence
# detection, and the candidate query reads recordings of every account by
# start time, which only the per-account index covered.
class AddTogetherDetection < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :together_detection_enabled, :boolean, default: true, null: false
    add_index :workouts, :started_at, where: "origin = 'import'", name: "index_workouts_on_recording_started_at"
  end
end
