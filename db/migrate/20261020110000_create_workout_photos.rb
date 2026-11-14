# frozen_string_literal: true

# Photos on workouts (PLAN_PHOTOS.md §2): one row per photo, its original kept
# for the owner and two stripped WebP derivatives attached through Active
# Storage, the camera's wall clock and position read from EXIF, and the bytes
# the account's photo quota counts. The gallery order is unique per workout
# and deferred, so two photos swap places in one transaction.
class CreateWorkoutPhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_photos do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }, index: { unique: true }
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.text :caption
      t.string :status, null: false, default: "processing"
      t.string :failure_reason
      t.string :original_content_type, null: false
      t.integer :width
      t.integer :height
      t.datetime :taken_at_local
      t.integer :taken_at_utc_offset
      t.st_point :exif_location, geographic: true, srid: 4326
      t.bigint :bytes_total, null: false, default: 0
      t.timestamps

      t.unique_constraint %i[workout_id position], deferrable: :deferred, name: "workout_photos_position_unique"
      t.check_constraint "status IN ('processing', 'ready', 'failed')", name: "workout_photos_status"
      t.check_constraint "failure_reason IS NULL OR failure_reason IN ('unreadable', 'too_large_dimensions', 'processing_error')",
                         name: "workout_photos_failure_reason"
      t.check_constraint "original_content_type IN ('image/jpeg', 'image/png', 'image/webp', 'image/heic')",
                         name: "workout_photos_original_content_type"
      t.check_constraint "position >= 0 AND bytes_total >= 0", name: "workout_photos_counters"
      t.check_constraint "caption IS NULL OR char_length(caption) <= 500", name: "workout_photos_caption_length"
      t.check_constraint "(width IS NULL AND height IS NULL) OR (width > 0 AND height > 0)", name: "workout_photos_dimensions"
      t.check_constraint "taken_at_utc_offset IS NULL OR taken_at_utc_offset BETWEEN -50400 AND 50400",
                         name: "workout_photos_utc_offset"
    end

    add_column :users, :photo_quota_bytes, :bigint
    add_check_constraint :users, "photo_quota_bytes IS NULL OR photo_quota_bytes >= 0", name: "users_photo_quota_bytes"
  end
end
