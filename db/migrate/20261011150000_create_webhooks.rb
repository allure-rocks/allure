# frozen_string_literal: true

# docs/dev/API.md: an account's webhook endpoints, the events emitted to
# them with their payload frozen, and one delivery chain per (event,
# endpoint).
class CreateWebhooks < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_endpoints do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :url, null: false
      t.string :description
      t.string :events, array: true, null: false, default: []
      t.text :secret, null: false
      t.text :previous_secret
      t.datetime :previous_secret_expires_at
      t.boolean :active, null: false, default: true
      t.datetime :disabled_at
      t.string :disabled_reason
      t.integer :consecutive_failures, null: false, default: 0
      t.datetime :first_failure_at
      t.timestamps

      t.index :uuid, unique: true
    end
    add_check_constraint :webhook_endpoints, "char_length(url) BETWEEN 1 AND 2048", name: "webhook_endpoints_url_length"
    add_check_constraint :webhook_endpoints, "description IS NULL OR char_length(description) <= 200",
                         name: "webhook_endpoints_description_length"
    add_check_constraint :webhook_endpoints, "cardinality(events) > 0", name: "webhook_endpoints_events"
    add_check_constraint :webhook_endpoints,
                         "(disabled_at IS NULL AND disabled_reason IS NULL) OR " \
                         "(disabled_at IS NOT NULL AND disabled_reason IN ('failing', 'gone', 'operator'))",
                         name: "webhook_endpoints_disabled"
    add_check_constraint :webhook_endpoints, "consecutive_failures >= 0", name: "webhook_endpoints_failures"

    create_table :webhook_events do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :event_type, null: false
      t.string :dedupe_key, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps

      t.index :uuid, unique: true
      t.index %i[user_id dedupe_key], unique: true
      t.index :created_at
    end
    add_check_constraint :webhook_events, "jsonb_typeof(payload) = 'object'", name: "webhook_events_payload_object"

    create_table :webhook_deliveries do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :webhook_event, null: false, foreign_key: { on_delete: :cascade }
      t.references :webhook_endpoint, null: false, foreign_key: { on_delete: :cascade }
      t.references :redelivery_of, foreign_key: { to_table: :webhook_deliveries, on_delete: :nullify }
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.integer :last_status_code
      t.string :last_error
      t.datetime :last_attempt_at
      t.datetime :succeeded_at
      t.timestamps

      t.index :uuid, unique: true
      t.index %i[status next_attempt_at]
      t.index %i[webhook_endpoint_id created_at]
    end
    add_check_constraint :webhook_deliveries, "status IN ('pending', 'succeeded', 'failed', 'abandoned')",
                         name: "webhook_deliveries_status"
    add_check_constraint :webhook_deliveries, "attempts >= 0", name: "webhook_deliveries_attempts"
  end
end
