# frozen_string_literal: true

class TightenWorkoutPhotoConstraints < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :workout_photos, name: "workout_photos_failure_reason",
      expression: "failure_reason IS NULL OR failure_reason IN ('unreadable', 'too_large_dimensions', 'processing_error')"
    add_check_constraint :workout_photos,
      "failure_reason IS NULL OR failure_reason IN ('unreadable', 'too_large_dimensions', 'processing_error', 'quota_exceeded')",
      name: "workout_photos_failure_reason"
    remove_check_constraint :workout_photos, name: "workout_photos_dimensions",
      expression: "(width IS NULL AND height IS NULL) OR (width > 0 AND height > 0)"
    add_check_constraint :workout_photos,
      "(width IS NULL AND height IS NULL) OR (width IS NOT NULL AND height IS NOT NULL AND width > 0 AND height > 0)",
      name: "workout_photos_dimensions"
  end
end
