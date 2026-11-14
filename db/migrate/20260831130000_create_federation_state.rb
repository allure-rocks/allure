# frozen_string_literal: true

class CreateFederationState < ActiveRecord::Migration[8.1]
  def change
    create_table :followings do |t|
      t.references :follower_actor, null: false, foreign_key: { to_table: :actors, on_delete: :restrict }
      t.references :followed_actor, null: false, foreign_key: { to_table: :actors, on_delete: :restrict }
      t.text :uri, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :requested_at, null: false
      t.datetime :accepted_at
      t.datetime :undone_at
      t.jsonb :raw
      t.timestamps
    end
    add_index :followings, :uri, unique: true
    add_index :followings, [ :follower_actor_id, :followed_actor_id ], unique: true,
              where: "status <> 'undone'", name: "index_active_followings_on_actor_pair"
    add_index :followings, [ :followed_actor_id, :status ]
    add_check_constraint :followings, "follower_actor_id <> followed_actor_id", name: "followings_no_self_follow"
    add_check_constraint :followings,
                         "status IN ('pending', 'accepted', 'rejected', 'undone')",
                         name: "followings_status"
    add_check_constraint :followings,
                         "(status = 'accepted') = (accepted_at IS NOT NULL)",
                         name: "followings_accepted_timestamp"
    add_check_constraint :followings,
                         "(status = 'undone') = (undone_at IS NOT NULL)",
                         name: "followings_undone_timestamp"

    create_table :federation_inbox_items do |t|
      t.references :recipient_actor, null: false, foreign_key: { to_table: :actors, on_delete: :restrict }
      t.text :activity_uri, null: false
      t.string :activity_type
      t.text :actor_uri
      t.string :raw_body_digest, null: false
      t.jsonb :raw, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.datetime :processed_at
      t.text :last_error
      t.timestamps
    end
    add_index :federation_inbox_items, [ :recipient_actor_id, :activity_uri ], unique: true,
              name: "index_inbox_items_on_recipient_and_activity"
    add_index :federation_inbox_items, [ :status, :next_attempt_at ]
    add_check_constraint :federation_inbox_items, "attempts BETWEEN 0 AND 10", name: "inbox_attempts"
    add_check_constraint :federation_inbox_items,
                         "status IN ('pending', 'processing', 'processed', 'rejected', 'failed')",
                         name: "inbox_status"

    create_table :federation_outbox_events do |t|
      t.references :actor, null: false, foreign_key: { to_table: :actors, on_delete: :restrict }
      t.string :subject_type, null: false
      t.bigint :subject_id
      t.uuid :event_uuid, null: false
      t.string :activity_type, null: false
      t.text :activity_uri, null: false
      t.text :object_uri, null: false
      t.jsonb :payload, null: false
      t.jsonb :audience, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.timestamps
    end
    add_index :federation_outbox_events, :event_uuid, unique: true
    add_index :federation_outbox_events, :activity_uri, unique: true
    add_index :federation_outbox_events, [ :actor_id, :object_uri, :created_at ]
    add_check_constraint :federation_outbox_events,
                         "subject_type IN ('WorkoutPublication', 'Actor')",
                         name: "outbox_subject_type"
    add_check_constraint :federation_outbox_events,
                         "activity_type IN ('Create', 'Delete', 'Undo', 'Follow', 'Accept', 'Like')",
                         name: "outbox_activity_type"
    add_check_constraint :federation_outbox_events,
                         "status IN ('pending', 'expanded', 'complete', 'cancelled', 'failed')",
                         name: "outbox_status"
    add_check_constraint :federation_outbox_events, "attempts >= 0", name: "outbox_attempts"

    create_table :federation_deliveries do |t|
      t.references :outbox_event, null: false,
                   foreign_key: { to_table: :federation_outbox_events, on_delete: :restrict }
      t.text :inbox_url, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.integer :last_response_status
      t.text :last_error
      t.boolean :gone_recovery_used, null: false, default: false
      t.datetime :lease_until
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :federation_deliveries, [ :outbox_event_id, :inbox_url ], unique: true,
              name: "index_deliveries_on_event_and_inbox"
    add_index :federation_deliveries, [ :status, :next_attempt_at, :lease_until ]
    add_check_constraint :federation_deliveries,
                         "status IN ('pending', 'delivering', 'reconciling', 'delivered', 'retrying', 'cancelled', 'failed')",
                         name: "delivery_status"
    add_check_constraint :federation_deliveries, "attempts >= 0", name: "delivery_attempts"

    create_table :federation_delivery_recipients do |t|
      t.references :delivery, null: false, foreign_key: { to_table: :federation_deliveries, on_delete: :cascade }
      t.text :actor_uri, null: false
      t.string :status, null: false, default: "pending"
      t.timestamps
    end
    add_index :federation_delivery_recipients, [ :delivery_id, :actor_uri ], unique: true,
              name: "index_delivery_recipients_on_delivery_and_actor"
    add_check_constraint :federation_delivery_recipients,
                         "status IN ('pending', 'authorized', 'withdrawn')",
                         name: "delivery_recipient_status"

    create_table :federation_likes do |t|
      t.references :actor, null: false, foreign_key: { to_table: :actors, on_delete: :restrict }
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }
      t.text :uri, null: false
      t.datetime :undone_at
      t.timestamps
    end
    add_index :federation_likes, :uri, unique: true
    add_index :federation_likes, [ :actor_id, :workout_id ], unique: true,
              where: "undone_at IS NULL", name: "index_active_likes_on_actor_and_workout"
  end
end
