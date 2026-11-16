# frozen_string_literal: true

# docs/dev/IMPORT-SOURCES.md: the bytes a batch's upload weighed, kept after
# its files are purged so the account's daily upload budget still counts it.
class AddSourceBytesToWorkoutImportBatches < ActiveRecord::Migration[8.1]
  def up
    add_column :workout_import_batches, :source_bytes, :bigint, default: 0, null: false
    add_check_constraint :workout_import_batches, "source_bytes >= 0", name: "workout_import_batches_source_bytes"

    execute <<~SQL.squish
      UPDATE workout_import_batches
      SET source_bytes = uploads.bytes
      FROM (
        SELECT active_storage_attachments.record_id, SUM(active_storage_blobs.byte_size) AS bytes
        FROM active_storage_attachments
        JOIN active_storage_blobs ON active_storage_blobs.id = active_storage_attachments.blob_id
        WHERE active_storage_attachments.record_type = 'WorkoutImportBatch'
          AND active_storage_attachments.name = 'source_files'
        GROUP BY active_storage_attachments.record_id
      ) AS uploads
      WHERE uploads.record_id = workout_import_batches.id
    SQL
  end

  def down
    remove_check_constraint :workout_import_batches, name: "workout_import_batches_source_bytes"
    remove_column :workout_import_batches, :source_bytes
  end
end
