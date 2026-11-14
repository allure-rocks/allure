# frozen_string_literal: true

# PLAN_API.md §5: the first response to a POST carrying an Idempotency-Key,
# kept 24 hours per (token, key) and replayed to a retry. A row without a
# status is a request still in flight.
class CreateApiIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_idempotency_keys do |t|
      t.references :api_token, null: false, foreign_key: { on_delete: :cascade }
      t.string :key, null: false
      t.string :request_digest, null: false
      t.integer :response_status
      t.jsonb :response_headers, null: false, default: {}
      t.text :response_body
      t.datetime :expires_at, null: false
      t.timestamps

      t.index %i[api_token_id key], unique: true
      t.index :expires_at
    end

    add_check_constraint :api_idempotency_keys, "char_length(key) BETWEEN 1 AND 255", name: "api_idempotency_keys_key_length"
    add_check_constraint :api_idempotency_keys, "request_digest ~ '^[0-9a-f]{64}$'", name: "api_idempotency_keys_digest"
  end
end
