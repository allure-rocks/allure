# frozen_string_literal: true

class AddSourceDigestToWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :workouts, :source_digest, :string, limit: 64
    add_index :workouts, [ :user_id, :source_digest ],
              unique: true,
              where: "source_digest IS NOT NULL",
              name: "index_workouts_on_user_and_source_digest"
  end
end
