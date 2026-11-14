class CreateRemoteSegmentRecipients < ActiveRecord::Migration[8.1]
  def change
    create_table :remote_segment_recipients do |t|
      t.bigint :remote_segment_id, null: false
      t.bigint :recipient_actor_id, null: false
      t.string :status, null: false, default: "active"
      t.datetime :withdrawn_at
      t.string :withdrawal_reason
      t.bigint :inbox_item_id
      t.timestamps
    end

    add_index :remote_segment_recipients, [ :remote_segment_id, :recipient_actor_id ],
              unique: true, name: "index_remote_segment_recipients_on_segment_and_actor"
    add_index :remote_segment_recipients, [ :recipient_actor_id, :status, :remote_segment_id ],
              name: "index_remote_segment_recipients_on_recipient_and_status"
    add_index :remote_segment_recipients, :remote_segment_id

    add_foreign_key :remote_segment_recipients, :remote_segments, on_delete: :cascade
    add_foreign_key :remote_segment_recipients, :actors, column: :recipient_actor_id
    add_foreign_key :remote_segment_recipients, :federation_inbox_items,
                    column: :inbox_item_id, on_delete: :nullify

    add_check_constraint :remote_segment_recipients,
                         "status IN ('active', 'withdrawn')",
                         name: "remote_segment_recipients_status"
    add_check_constraint :remote_segment_recipients,
                         "(status = 'withdrawn') = (withdrawn_at IS NOT NULL)",
                         name: "remote_segment_recipients_withdrawal_state"
    add_check_constraint :remote_segment_recipients,
                         "withdrawal_reason IS NULL OR withdrawal_reason IN ('unfollow', 'rejected', 'blocked', 'deleted', 'unreachable')",
                         name: "remote_segment_recipients_withdrawal_reason"
  end
end
