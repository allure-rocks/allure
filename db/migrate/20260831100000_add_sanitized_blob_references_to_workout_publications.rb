# frozen_string_literal: true

class AddSanitizedBlobReferencesToWorkoutPublications < ActiveRecord::Migration[8.1]
  def up
    add_reference :workout_publications,
                  :sanitized_gpx_blob,
                  foreign_key: { to_table: :active_storage_blobs },
                  null: true
    add_reference :workout_publications,
                  :sanitized_route_image_blob,
                  foreign_key: { to_table: :active_storage_blobs },
                  null: true

    backfill_blob_reference(:gpx)
    backfill_blob_reference(:route_image)
  end

  def down
    remove_reference :workout_publications, :sanitized_gpx_blob
    remove_reference :workout_publications, :sanitized_route_image_blob
  end

  private

  def backfill_blob_reference(name)
    column = "sanitized_#{name}_blob_id"

    execute <<~SQL
      UPDATE workout_publications
      SET #{column} = (
        SELECT blob_id
        FROM active_storage_attachments
        WHERE record_type = 'WorkoutPublication'
          AND record_id = workout_publications.id
          AND name = '#{name}'
        ORDER BY id DESC
        LIMIT 1
      )
      WHERE EXISTS (
        SELECT 1
        FROM active_storage_attachments
        WHERE record_type = 'WorkoutPublication'
          AND record_id = workout_publications.id
          AND name = '#{name}'
      )
    SQL
  end
end
