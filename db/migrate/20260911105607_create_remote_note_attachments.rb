class CreateRemoteNoteAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :remote_note_attachments do |t|
      t.bigint :remote_note_id, null: false
      t.string :kind, null: false
      t.text :remote_url, null: false
      t.string :media_type
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.text :last_error
      t.bigint :blob_id
      t.string :content_digest
      t.integer :byte_size
      t.datetime :fetched_at
      t.datetime :purged_at
      t.timestamps
    end

    add_index :remote_note_attachments, [ :remote_note_id, :kind ], unique: true
    add_index :remote_note_attachments, [ :status, :next_attempt_at ]
    add_index :remote_note_attachments, :blob_id

    add_foreign_key :remote_note_attachments, :remote_notes, on_delete: :cascade
    add_foreign_key :remote_note_attachments, :active_storage_blobs, column: :blob_id

    add_check_constraint :remote_note_attachments,
                         "kind IN ('gpx', 'route_image')",
                         name: "remote_note_attachments_kind"
    add_check_constraint :remote_note_attachments,
                         "status IN ('pending', 'fetching', 'cached', 'failed', 'unavailable', 'purged')",
                         name: "remote_note_attachments_status"
    add_check_constraint :remote_note_attachments,
                         "attempts >= 0",
                         name: "remote_note_attachments_attempts"
    add_check_constraint :remote_note_attachments,
                         "char_length(remote_url) > 0",
                         name: "remote_note_attachments_remote_url"
  end
end
