# frozen_string_literal: true

# PLAN_PUSH.md §5: one push subscription per signed-in session. It goes with
# its session (sign-out, expiry, revocation) through the cascade, so no push
# reaches a device for an account it no longer holds. The endpoint and the
# device's `auth` secret are encrypted; the digest finds a row by endpoint.
class CreatePushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :session, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.text :endpoint, null: false
      t.string :endpoint_digest, null: false
      t.string :p256dh, null: false
      t.text :auth, null: false
      t.boolean :hide_content, null: false, default: false
      t.datetime :last_success_at
      t.integer :failure_count, null: false, default: 0
      t.timestamps

      t.index :endpoint_digest, unique: true
    end
    add_check_constraint :push_subscriptions, "char_length(endpoint_digest) = 64",
                         name: "push_subscriptions_endpoint_digest"
    add_check_constraint :push_subscriptions, "failure_count >= 0", name: "push_subscriptions_failure_count"
  end
end
