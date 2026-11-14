# frozen_string_literal: true

# PLAN_COMMENTS.md §3.1: one row per comment or reply, local or remote, on the
# thread its target hosts — a local workout, or a received note whose origin
# hosts the thread. A comment is never edited: deletion by its author, removal
# by the thread host and refusal by the origin are durable states that keep the
# row and its identity, so a late Delete or a duplicate Create still resolves.
class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :actor, null: false, foreign_key: { on_delete: :restrict }
      t.references :workout, index: false, foreign_key: { on_delete: :cascade }
      t.references :remote_note, index: false, foreign_key: { on_delete: :cascade }
      t.references :parent, foreign_key: { to_table: :comments, on_delete: :nullify }
      t.text :in_reply_to_uri, null: false
      t.text :uri, null: false
      t.text :activity_uri
      t.string :audience, null: false
      t.string :status, null: false, default: "active"
      t.string :removal_reason
      t.text :body, null: false
      t.text :content_html
      t.datetime :published_at, null: false
      t.datetime :deleted_at
      t.datetime :removed_at
      t.datetime :rejected_at
      t.string :source_domain
      t.jsonb :raw, null: false, default: {}
      t.jsonb :warnings, null: false, default: []
      t.timestamps
    end

    add_index :comments, :uuid, unique: true
    add_index :comments, :uri, unique: true
    add_index :comments, :activity_uri
    add_index :comments, :in_reply_to_uri
    add_index :comments, [ :workout_id, :created_at ]
    add_index :comments, [ :remote_note_id, :created_at ]

    add_check_constraint :comments,
                         "((workout_id IS NOT NULL)::int + (remote_note_id IS NOT NULL)::int) = 1",
                         name: "comments_single_target"
    add_check_constraint :comments,
                         "status IN ('active', 'deleted', 'removed', 'rejected')",
                         name: "comments_status"
    add_check_constraint :comments,
                         "audience IN ('public', 'followers')",
                         name: "comments_audience"
    add_check_constraint :comments,
                         "removal_reason IS NULL OR removal_reason IN ('owner', 'blocked', 'actor_deleted', " \
                         "'closed', 'not_allowed', 'inactive', 'full', 'unknown')",
                         name: "comments_removal_reason"
    add_check_constraint :comments,
                         "char_length(body) BETWEEN 1 AND 2000",
                         name: "comments_body_length"
    # Every non-active state carries its own instant, and only the host-side
    # states carry a reason: a deletion is the author's own decision.
    add_check_constraint :comments,
                         "(status = 'deleted') = (deleted_at IS NOT NULL)",
                         name: "comments_deleted_state"
    add_check_constraint :comments,
                         "(status = 'removed') = (removed_at IS NOT NULL)",
                         name: "comments_removed_state"
    add_check_constraint :comments,
                         "(status = 'rejected') = (rejected_at IS NOT NULL)",
                         name: "comments_rejected_state"
    add_check_constraint :comments,
                         "(status IN ('removed', 'rejected')) = (removal_reason IS NOT NULL)",
                         name: "comments_removal_reason_state"
    add_check_constraint :comments,
                         "jsonb_typeof(raw) = 'object' AND jsonb_typeof(warnings) = 'array'",
                         name: "comments_json_shapes"
  end
end
