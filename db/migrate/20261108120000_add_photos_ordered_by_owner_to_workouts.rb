# frozen_string_literal: true

# PLAN_PHOTOS.md §2.1: the gallery follows the capture time until the owner
# reorders it by hand. A workout whose current order already differs from the
# upload order keeps that order: the owner chose it.
class AddPhotosOrderedByOwnerToWorkouts < ActiveRecord::Migration[8.1]
  def up
    add_column :workouts, :photos_ordered_by_owner, :boolean, null: false, default: false

    execute <<~SQL
      UPDATE workouts SET photos_ordered_by_owner = TRUE
      WHERE id IN (
        SELECT workout_id FROM workout_photos
        GROUP BY workout_id
        HAVING array_agg(id ORDER BY position, id) <> array_agg(id ORDER BY id)
      )
    SQL
  end

  def down
    remove_column :workouts, :photos_ordered_by_owner
  end
end
