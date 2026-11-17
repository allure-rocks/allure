# frozen_string_literal: true

# The per-account in-app inbox (docs/dev/NOTIFICATIONS.md). One row per recipient
# and event: `actor` is who caused it, `subject` is the relationship it
# describes, and `read_at` is the cross-device read marker. The row is
# recipient-scoped and never carries coordinates, workout content, or remote
# HTML; it is withdrawn when the relationship behind it ends.
class CreateNotifications < ActiveRecord::Migration[8.1]
  KINDS = %w[follow_request follow_accepted].freeze

  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :actor, null: true, foreign_key: { on_delete: :nullify }, index: false
      t.string :subject_type
      t.bigint :subject_id
      t.string :kind, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :read_at
      t.timestamps
    end

    add_index :notifications, %i[user_id read_at]
    add_index :notifications, %i[user_id created_at]
    add_index :notifications, %i[subject_type subject_id]
    # One notification per recipient, kind, and relationship: redelivered
    # federation activities and re-requests resolve to the existing row.
    add_index :notifications, %i[user_id kind subject_type subject_id],
              unique: true,
              where: "subject_id IS NOT NULL",
              name: "index_notifications_on_user_kind_subject"
    add_check_constraint :notifications,
                         "kind::text = ANY (ARRAY[#{KINDS.map { |k| "'#{k}'::character varying" }.join(', ')}]::text[])",
                         name: "notifications_kind"
    add_check_constraint :notifications, "jsonb_typeof(payload) = 'object'",
                         name: "notifications_payload_object"
  end
end
