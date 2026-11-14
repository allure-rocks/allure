# frozen_string_literal: true

# Where a photo sits along its workout (PLAN_PHOTOS.md §4): the position in
# use, how it was found, and its distance and elapsed time along the
# recording. Owner-only. `cleared` is the owner's explicit removal, which an
# automatic placement never overrides, like `manual`. The workout carries the
# camera-clock correction applied to every time-placed photo.
class AddPlacementToWorkoutPhotos < ActiveRecord::Migration[8.1]
  def change
    change_table :workout_photos, bulk: true do |t|
      t.st_point :location, geographic: true, srid: 4326
      t.string :location_source, null: false, default: "none"
      t.float :track_distance
      t.float :track_elapsed
      t.check_constraint "location_source IN ('exif', 'time', 'manual', 'none', 'cleared')",
                         name: "workout_photos_location_source"
      t.check_constraint "(location IS NULL) = (location_source IN ('none', 'cleared'))",
                         name: "workout_photos_location_shape"
      t.check_constraint "(location IS NULL AND track_distance IS NULL AND track_elapsed IS NULL) " \
                         "OR (location IS NOT NULL AND track_distance >= 0 AND track_elapsed IS NOT NULL)",
                         name: "workout_photos_track_position"
    end

    add_column :workouts, :photo_time_offset_seconds, :integer, null: false, default: 0
    add_check_constraint :workouts, "photo_time_offset_seconds BETWEEN -50400 AND 50400",
                         name: "workouts_photo_time_offset"
  end
end
