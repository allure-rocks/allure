# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_11_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "postgis"

  create_table "account_exports", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.string "status", default: "pending", null: false
    t.bigint "byte_size"
    t.jsonb "counts", default: {}, null: false
    t.string "error_code"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status", "expires_at"], name: "index_account_exports_on_status_and_expires_at"
    t.index ["user_id"], name: "index_account_exports_on_user_id"
    t.index ["user_id"], name: "index_account_exports_one_in_progress", unique: true, where: "((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('running'::character varying)::text]))"
    t.index ["uuid"], name: "index_account_exports_on_uuid", unique: true
    t.check_constraint "status::text <> 'ready'::text OR expires_at IS NOT NULL AND completed_at IS NOT NULL", name: "account_exports_ready"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'running'::character varying::text, 'ready'::character varying::text, 'failed'::character varying::text, 'expired'::character varying::text])", name: "account_exports_status"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "actors", force: :cascade do |t|
    t.string "acct"
    t.datetime "avatar_cached_at"
    t.text "avatar_url"
    t.string "capability_profile", default: "unknown", null: false
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "handle"
    t.text "inbox_url"
    t.datetime "last_fetched_at"
    t.boolean "local", default: false, null: false
    t.text "private_key_ciphertext"
    t.datetime "private_key_retired_at"
    t.text "public_key_id"
    t.text "public_key_pem"
    t.jsonb "raw"
    t.text "shared_inbox_url"
    t.text "summary"
    t.datetime "tombstoned_at"
    t.datetime "updated_at", null: false
    t.text "uri", null: false
    t.bigint "user_id"
    t.index ["acct"], name: "index_actors_on_acct"
    t.index ["local", "last_fetched_at"], name: "index_actors_on_local_and_last_fetched_at"
    t.index ["tombstoned_at"], name: "index_actors_on_tombstoned_at"
    t.index ["uri"], name: "index_actors_on_uri", unique: true
    t.index ["user_id"], name: "index_local_actors_on_user_id", unique: true, where: "(local = true)"
    t.check_constraint "capability_profile::text = ANY (ARRAY['unknown'::character varying::text, 'public_only'::character varying::text, 'restricted_fetch'::character varying::text, 'restricted_shared_inbox'::character varying::text])", name: "actors_capability_profile"
    t.check_constraint "local = false OR user_id IS NOT NULL OR tombstoned_at IS NOT NULL", name: "actors_local_owner"
    t.check_constraint "local = true OR user_id IS NULL AND private_key_ciphertext IS NULL", name: "actors_remote_identity"
  end

  create_table "admin_events", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "subject_id"
    t.string "subject_type"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["action"], name: "index_admin_events_on_action"
    t.index ["subject_type", "subject_id"], name: "index_admin_events_on_subject_type_and_subject_id"
    t.index ["user_id"], name: "index_admin_events_on_user_id"
    t.check_constraint "action::text = ANY (ARRAY['domain_blocked'::character varying::text, 'domain_unblocked'::character varying::text, 'actor_blocked'::character varying::text, 'actor_unblocked'::character varying::text, 'peer_policy_set'::character varying::text, 'peer_policy_removed'::character varying::text, 'media_retried'::character varying::text, 'job_retried'::character varying::text, 'job_discarded'::character varying::text, 'jobs_retried'::character varying::text, 'jobs_discarded'::character varying::text, 'queue_paused'::character varying::text, 'queue_resumed'::character varying::text, 'analysis_backfill_enqueued'::character varying::text, 'elevation_backfill_enqueued'::character varying::text, 'places_backfill_enqueued'::character varying::text, 'toponymy_backfill_enqueued'::character varying::text, 'import_redetection_enqueued'::character varying::text, 'workouts_rebuild_enqueued'::character varying::text, 'route_images_backfill_enqueued'::character varying::text, 'segment_route_images_backfill_enqueued'::character varying::text, 'loop_reuse_backfill_enqueued'::character varying::text, 'elevation_profiles_backfill_enqueued'::character varying::text, 'publication_withdrawn'::character varying::text, 'publication_schedule_cancelled'::character varying::text, 'account_suspended'::character varying::text, 'account_reinstated'::character varying::text, 'invitation_created'::character varying::text, 'invitation_revoked'::character varying::text, 'second_factor_reset'::character varying::text, 'password_setup_sent'::character varying::text, 'import_connection_revoked'::character varying::text, 'api_token_revoked'::character varying::text, 'webhook_endpoint_disabled'::character varying::text, 'segment_places_backfill_enqueued'::character varying::text, 'together_detection_backfill_enqueued'::character varying::text, 'account_deletion_scheduled'::character varying::text, 'account_deletion_cancelled'::character varying::text, 'account_deleted'::character varying::text, 'weather_backfill_enqueued'::character varying::text, 'segment_terrain_elevation_backfill_enqueued'::character varying::text, 'heart_rate_backfill_enqueued'::character varying::text, 'photo_quota_changed'::character varying::text, 'funding_granted'::character varying::text, 'funding_revoked'::character varying::text, 'funding_attached'::character varying::text, 'route_suggestions_backfill_enqueued'::character varying::text])", name: "admin_events_action"
    t.check_constraint "jsonb_typeof(metadata) = 'object'::text", name: "admin_events_metadata_object"
  end

  create_table "api_idempotency_keys", force: :cascade do |t|
    t.bigint "api_token_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.string "request_digest", null: false
    t.text "response_body"
    t.jsonb "response_headers", default: {}, null: false
    t.integer "response_status"
    t.datetime "updated_at", null: false
    t.index ["api_token_id", "key"], name: "index_api_idempotency_keys_on_api_token_id_and_key", unique: true
    t.index ["api_token_id"], name: "index_api_idempotency_keys_on_api_token_id"
    t.index ["expires_at"], name: "index_api_idempotency_keys_on_expires_at"
    t.check_constraint "char_length(key::text) >= 1 AND char_length(key::text) <= 255", name: "api_idempotency_keys_key_length"
    t.check_constraint "request_digest::text ~ '^[0-9a-f]{64}$'::text", name: "api_idempotency_keys_digest"
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.string "mcp_geometry", default: "none", null: false
    t.string "name", null: false
    t.datetime "revoked_at"
    t.string "revoked_by"
    t.string "scopes", default: [], null: false, array: true
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id", "revoked_at"], name: "index_api_tokens_on_user_id_and_revoked_at"
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
    t.index ["uuid"], name: "index_api_tokens_on_uuid", unique: true
    t.check_constraint "cardinality(scopes) > 0 AND scopes <@ ARRAY['read'::character varying, 'write'::character varying, 'import'::character varying, 'publish'::character varying, 'social:read'::character varying, 'webhooks'::character varying]", name: "api_tokens_scopes"
    t.check_constraint "char_length(name::text) >= 1 AND char_length(name::text) <= 80", name: "api_tokens_name_length"
    t.check_constraint "expires_at <= (created_at + 'P366D'::interval)", name: "api_tokens_expiry"
    t.check_constraint "mcp_geometry::text = ANY (ARRAY['none'::character varying::text, 'filtered'::character varying::text, 'raw'::character varying::text])", name: "api_tokens_mcp_geometry"
    t.check_constraint "revoked_at IS NULL AND revoked_by IS NULL OR revoked_at IS NOT NULL AND (revoked_by::text = ANY (ARRAY['owner'::character varying::text, 'operator'::character varying::text, 'system'::character varying::text]))", name: "api_tokens_revocation"
    t.check_constraint "token_digest::text ~ '^[0-9a-f]{64}$'::text", name: "api_tokens_digest_format"
  end

  create_table "best_efforts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "distance_key", null: false
    t.decimal "distance_meters", precision: 14, scale: 3, null: false
    t.integer "duration_seconds", null: false
    t.decimal "end_offset_meters", precision: 14, scale: 3
    t.bigint "sport_id", null: false
    t.decimal "start_offset_meters", precision: 14, scale: 3
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_id", null: false
    t.index ["sport_id"], name: "index_best_efforts_on_sport_id"
    t.index ["user_id", "sport_id", "distance_key", "duration_seconds"], name: "index_best_efforts_on_user_sport_distance_duration"
    t.index ["user_id"], name: "index_best_efforts_on_user_id"
    t.index ["workout_id", "distance_key"], name: "index_best_efforts_on_workout_id_and_distance_key", unique: true
    t.index ["workout_id"], name: "index_best_efforts_on_workout_id"
    t.check_constraint "(start_offset_meters IS NULL OR start_offset_meters >= 0::numeric) AND (end_offset_meters IS NULL OR end_offset_meters >= 0::numeric)", name: "best_efforts_offsets"
    t.check_constraint "distance_meters > 0::numeric AND duration_seconds > 0", name: "best_efforts_positive_metrics"
    t.check_constraint "start_offset_meters IS NULL OR end_offset_meters IS NULL OR end_offset_meters >= start_offset_meters", name: "best_efforts_end_offset"
  end

  create_table "comments", force: :cascade do |t|
    t.text "activity_uri"
    t.bigint "actor_id", null: false
    t.string "audience", null: false
    t.text "body", null: false
    t.datetime "confirmed_at"
    t.text "content_html"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "in_reply_to_uri", null: false
    t.bigint "parent_id"
    t.datetime "published_at", null: false
    t.jsonb "raw", default: {}, null: false
    t.datetime "rejected_at"
    t.text "relay_activity_uri"
    t.bigint "relayed_by_actor_id"
    t.bigint "remote_note_id"
    t.string "removal_reason"
    t.datetime "removed_at"
    t.string "source_domain"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.text "uri", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.jsonb "warnings", default: [], null: false
    t.bigint "workout_id"
    t.index ["activity_uri"], name: "index_comments_on_activity_uri"
    t.index ["actor_id"], name: "index_comments_on_actor_id"
    t.index ["in_reply_to_uri"], name: "index_comments_on_in_reply_to_uri"
    t.index ["parent_id"], name: "index_comments_on_parent_id"
    t.index ["relay_activity_uri"], name: "index_comments_on_relay_activity_uri"
    t.index ["remote_note_id", "created_at"], name: "index_comments_on_remote_note_id_and_created_at"
    t.index ["uri"], name: "index_comments_on_uri", unique: true
    t.index ["uuid"], name: "index_comments_on_uuid", unique: true
    t.index ["workout_id", "created_at"], name: "index_comments_on_workout_id_and_created_at"
    t.check_constraint "((workout_id IS NOT NULL)::integer + (remote_note_id IS NOT NULL)::integer) = 1", name: "comments_single_target"
    t.check_constraint "(status::text = 'deleted'::text) = (deleted_at IS NOT NULL)", name: "comments_deleted_state"
    t.check_constraint "(status::text = 'rejected'::text) = (rejected_at IS NOT NULL)", name: "comments_rejected_state"
    t.check_constraint "(status::text = 'removed'::text) = (removed_at IS NOT NULL)", name: "comments_removed_state"
    t.check_constraint "(status::text = ANY (ARRAY['removed'::character varying::text, 'rejected'::character varying::text])) = (removal_reason IS NOT NULL)", name: "comments_removal_reason_state"
    t.check_constraint "audience::text = ANY (ARRAY['public'::character varying::text, 'followers'::character varying::text])", name: "comments_audience"
    t.check_constraint "char_length(body) <= 2000 AND (status::text <> 'active'::text OR char_length(body) >= 1)", name: "comments_body_length"
    t.check_constraint "jsonb_typeof(raw) = 'object'::text AND jsonb_typeof(warnings) = 'array'::text", name: "comments_json_shapes"
    t.check_constraint "removal_reason IS NULL OR (removal_reason::text = ANY (ARRAY['owner'::character varying::text, 'blocked'::character varying::text, 'actor_deleted'::character varying::text, 'closed'::character varying::text, 'not_allowed'::character varying::text, 'inactive'::character varying::text, 'full'::character varying::text, 'unknown'::character varying::text]))", name: "comments_removal_reason"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'deleted'::character varying::text, 'removed'::character varying::text, 'rejected'::character varying::text])", name: "comments_status"
  end

  create_table "detected_laps", force: :cascade do |t|
    t.decimal "ascent", precision: 12, scale: 2
    t.integer "average_cadence"
    t.decimal "average_grade", precision: 5, scale: 2
    t.integer "average_heart_rate"
    t.integer "average_pace"
    t.integer "average_power"
    t.decimal "average_speed", precision: 10, scale: 4
    t.decimal "climb_score", precision: 14, scale: 2
    t.datetime "created_at", null: false
    t.decimal "descent", precision: 12, scale: 2
    t.integer "detector_version", null: false
    t.decimal "distance", precision: 14, scale: 3, null: false
    t.integer "elapsed_time", null: false
    t.decimal "end_distance", precision: 14, scale: 3, null: false
    t.integer "end_point_index", null: false
    t.integer "grade_adjusted_pace"
    t.decimal "max_grade", precision: 5, scale: 2
    t.integer "max_heart_rate"
    t.integer "max_power"
    t.decimal "max_speed", precision: 10, scale: 4
    t.integer "moving_time", null: false
    t.string "name"
    t.integer "number", null: false
    t.bigint "segment_effort_id"
    t.string "source", null: false
    t.decimal "start_distance", precision: 14, scale: 3, null: false
    t.integer "start_point_index", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "workout_id", null: false
    t.index ["segment_effort_id"], name: "index_detected_laps_on_segment_effort_id"
    t.index ["workout_id", "source", "number"], name: "index_detected_laps_on_workout_id_and_source_and_number", unique: true
    t.index ["workout_id", "start_distance"], name: "index_detected_laps_on_workout_id_and_start_distance"
    t.check_constraint "(average_grade IS NULL OR average_grade >= 0::numeric) AND (max_grade IS NULL OR max_grade >= 0::numeric) AND (climb_score IS NULL OR climb_score >= 0::numeric)", name: "detected_laps_climb_metrics"
    t.check_constraint "(average_pace IS NULL OR average_pace >= 0) AND (average_heart_rate IS NULL OR average_heart_rate >= 0) AND (max_heart_rate IS NULL OR max_heart_rate >= 0) AND (average_cadence IS NULL OR average_cadence >= 0) AND (average_power IS NULL OR average_power >= 0)", name: "detected_laps_physiological_metrics"
    t.check_constraint "detector_version > 0", name: "detected_laps_detector_version"
    t.check_constraint "distance >= 0::numeric AND (ascent IS NULL OR ascent >= 0::numeric) AND (descent IS NULL OR descent >= 0::numeric) AND (average_speed IS NULL OR average_speed >= 0::numeric) AND (max_speed IS NULL OR max_speed >= 0::numeric)", name: "detected_laps_non_negative_metrics"
    t.check_constraint "elapsed_time > 0", name: "detected_laps_elapsed_time"
    t.check_constraint "end_distance >= start_distance", name: "detected_laps_distances"
    t.check_constraint "end_point_index > start_point_index", name: "detected_laps_point_indexes"
    t.check_constraint "grade_adjusted_pace IS NULL OR grade_adjusted_pace >= 0", name: "detected_laps_grade_adjusted_pace"
    t.check_constraint "max_power IS NULL OR max_power >= 0", name: "detected_laps_max_power"
    t.check_constraint "moving_time >= 0 AND moving_time <= elapsed_time", name: "detected_laps_moving_time"
    t.check_constraint "name IS NULL OR char_length(name::text) <= 120", name: "detected_laps_name_length"
    t.check_constraint "number >= 1", name: "detected_laps_number"
    t.check_constraint "source::text = ANY (ARRAY['loop'::character varying::text, 'route'::character varying::text, 'pause'::character varying::text, 'climb'::character varying::text, 'descent'::character varying::text, 'stop'::character varying::text, 'speed_interval'::character varying::text, 'power_interval'::character varying::text])", name: "detected_laps_source"
  end

  create_table "effort_records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "distance_key", null: false
    t.decimal "distance_meters", precision: 14, scale: 3, null: false
    t.integer "duration_seconds", null: false
    t.bigint "sport_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_id"
    t.datetime "workout_started_at", null: false
    t.index ["sport_id"], name: "index_effort_records_on_sport_id"
    t.index ["user_id", "sport_id", "distance_key"], name: "index_effort_records_on_user_id_and_sport_id_and_distance_key", unique: true
    t.index ["user_id"], name: "index_effort_records_on_user_id"
    t.index ["workout_id"], name: "index_effort_records_on_workout_id"
    t.check_constraint "distance_meters > 0::numeric AND duration_seconds > 0", name: "effort_records_positive_metrics"
  end

  create_table "equipment_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true, null: false
    t.string "label", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_equipment_types_on_slug", unique: true
  end

  create_table "equipments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.bigint "equipment_type_id", null: false
    t.string "external_id"
    t.bigint "import_connection_id"
    t.boolean "is_active", default: true, null: false
    t.string "label", null: false
    t.decimal "total_distance", precision: 14, scale: 3, default: "0.0", null: false
    t.integer "total_duration", default: 0, null: false
    t.integer "total_moving", default: 0, null: false
    t.integer "total_workouts", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["equipment_type_id"], name: "index_equipments_on_equipment_type_id"
    t.index ["import_connection_id", "external_id"], name: "index_equipments_on_import_connection_external_id", unique: true, where: "((import_connection_id IS NOT NULL) AND (external_id IS NOT NULL))"
    t.index ["user_id", "label"], name: "index_equipments_on_user_id_and_label", unique: true
    t.index ["user_id"], name: "index_equipments_on_user_id"
    t.index ["uuid"], name: "index_equipments_on_uuid", unique: true
    t.check_constraint "total_distance >= 0::numeric AND total_duration >= 0 AND total_moving >= 0 AND total_workouts >= 0", name: "equipments_non_negative_totals"
  end

  create_table "federation_actor_blocks", force: :cascade do |t|
    t.text "actor_uri", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "reason"
    t.datetime "updated_at", null: false
    t.index ["actor_uri"], name: "index_federation_actor_blocks_on_actor_uri", unique: true
    t.check_constraint "char_length(actor_uri) > 0", name: "federation_actor_blocks_uri"
  end

  create_table "federation_deliveries", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.boolean "gone_recovery_used", default: false, null: false
    t.text "inbox_url", null: false
    t.text "last_error"
    t.integer "last_response_status"
    t.datetime "lease_until"
    t.datetime "next_attempt_at"
    t.bigint "outbox_event_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["outbox_event_id", "inbox_url"], name: "index_deliveries_on_event_and_inbox", unique: true
    t.index ["outbox_event_id"], name: "index_federation_deliveries_on_outbox_event_id"
    t.index ["status", "next_attempt_at", "lease_until"], name: "idx_on_status_next_attempt_at_lease_until_c9d92ddc68"
    t.check_constraint "attempts >= 0", name: "delivery_attempts"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'delivering'::character varying::text, 'reconciling'::character varying::text, 'delivered'::character varying::text, 'retrying'::character varying::text, 'cancelled'::character varying::text, 'failed'::character varying::text])", name: "delivery_status"
  end

  create_table "federation_delivery_recipients", force: :cascade do |t|
    t.text "actor_uri", null: false
    t.datetime "created_at", null: false
    t.bigint "delivery_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_id", "actor_uri"], name: "index_delivery_recipients_on_delivery_and_actor", unique: true
    t.index ["delivery_id"], name: "index_federation_delivery_recipients_on_delivery_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'authorized'::character varying::text, 'withdrawn'::character varying::text])", name: "delivery_recipient_status"
  end

  create_table "federation_domain_blocks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "domain", null: false
    t.text "reason"
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_federation_domain_blocks_on_domain", unique: true
    t.check_constraint "char_length(domain::text) > 0", name: "federation_domain_blocks_domain"
  end

  create_table "federation_inbox_items", force: :cascade do |t|
    t.string "activity_type"
    t.text "activity_uri", null: false
    t.text "actor_uri"
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "last_error"
    t.datetime "next_attempt_at"
    t.datetime "processed_at"
    t.jsonb "raw", null: false
    t.string "raw_body_digest", null: false
    t.bigint "recipient_actor_id", null: false
    t.string "remote_domain", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["recipient_actor_id", "activity_uri"], name: "index_inbox_items_on_recipient_and_activity", unique: true
    t.index ["recipient_actor_id"], name: "index_federation_inbox_items_on_recipient_actor_id"
    t.index ["remote_domain", "created_at"], name: "index_federation_inbox_items_on_remote_domain_and_created_at"
    t.index ["status", "next_attempt_at"], name: "index_federation_inbox_items_on_status_and_next_attempt_at"
    t.check_constraint "attempts >= 0 AND attempts <= 10", name: "inbox_attempts"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'processed'::character varying::text, 'rejected'::character varying::text, 'failed'::character varying::text])", name: "inbox_status"
  end

  create_table "federation_outbox_events", force: :cascade do |t|
    t.string "activity_type", null: false
    t.text "activity_uri", null: false
    t.bigint "actor_id", null: false
    t.integer "attempts", default: 0, null: false
    t.jsonb "audience", null: false
    t.datetime "created_at", null: false
    t.uuid "event_uuid", null: false
    t.text "last_error"
    t.text "object_uri", null: false
    t.jsonb "payload", null: false
    t.text "payload_digest"
    t.datetime "payload_redacted_at"
    t.bigint "segment_publication_id"
    t.string "status", default: "pending", null: false
    t.bigint "subject_id"
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "workout_publication_id"
    t.index ["activity_uri"], name: "index_federation_outbox_events_on_activity_uri", unique: true
    t.index ["actor_id", "object_uri", "created_at"], name: "idx_on_actor_id_object_uri_created_at_8118f6c058"
    t.index ["actor_id"], name: "index_federation_outbox_events_on_actor_id"
    t.index ["event_uuid"], name: "index_federation_outbox_events_on_event_uuid", unique: true
    t.index ["segment_publication_id", "status"], name: "index_outbox_events_on_segment_publication_and_status"
    t.index ["status", "updated_at"], name: "index_outbox_events_on_recovery", where: "((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('expanded'::character varying)::text]))"
    t.index ["workout_publication_id", "status"], name: "index_outbox_events_on_publication_and_status"
    t.check_constraint "activity_type::text = ANY (ARRAY['Create'::character varying::text, 'Delete'::character varying::text, 'Undo'::character varying::text, 'Follow'::character varying::text, 'Accept'::character varying::text, 'Reject'::character varying::text, 'Like'::character varying::text, 'Announce'::character varying::text, 'Invite'::character varying::text])", name: "outbox_activity_type"
    t.check_constraint "attempts >= 0", name: "outbox_attempts"
    t.check_constraint "status::text = ANY (ARRAY['preparing'::character varying::text, 'pending'::character varying::text, 'expanded'::character varying::text, 'complete'::character varying::text, 'cancelled'::character varying::text, 'failed'::character varying::text])", name: "outbox_status"
    t.check_constraint "subject_type::text = 'WorkoutPublication'::text AND workout_publication_id IS NOT NULL AND subject_id = workout_publication_id AND segment_publication_id IS NULL OR subject_type::text = 'SegmentPublication'::text AND segment_publication_id IS NOT NULL AND subject_id = segment_publication_id AND workout_publication_id IS NULL OR subject_type::text = 'Actor'::text AND workout_publication_id IS NULL AND segment_publication_id IS NULL", name: "outbox_publication_subject_integrity"
    t.check_constraint "subject_type::text = ANY (ARRAY['WorkoutPublication'::character varying::text, 'SegmentPublication'::character varying::text, 'Actor'::character varying::text])", name: "outbox_subject_type"
  end

  create_table "federation_peer_policies", force: :cascade do |t|
    t.bigint "approved_by_id"
    t.string "capability_profile", default: "unknown", null: false
    t.datetime "created_at", null: false
    t.string "domain", null: false
    t.text "reason"
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_federation_peer_policies_on_domain", unique: true
    t.check_constraint "capability_profile::text = ANY (ARRAY['unknown'::character varying::text, 'public_only'::character varying::text, 'restricted_fetch'::character varying::text, 'restricted_shared_inbox'::character varying::text])", name: "federation_peer_policies_capability"
    t.check_constraint "char_length(domain::text) > 0", name: "federation_peer_policies_domain"
  end

  create_table "followings", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.bigint "followed_actor_id", null: false
    t.bigint "follower_actor_id", null: false
    t.jsonb "raw"
    t.datetime "requested_at", null: false
    t.string "status", default: "pending", null: false
    t.datetime "undone_at"
    t.datetime "updated_at", null: false
    t.text "uri", null: false
    t.index ["followed_actor_id", "status"], name: "index_followings_on_followed_actor_id_and_status"
    t.index ["followed_actor_id"], name: "index_followings_on_followed_actor_id"
    t.index ["follower_actor_id", "followed_actor_id"], name: "index_active_followings_on_actor_pair", unique: true, where: "((status)::text <> 'undone'::text)"
    t.index ["follower_actor_id"], name: "index_followings_on_follower_actor_id"
    t.index ["uri"], name: "index_followings_on_uri", unique: true
    t.check_constraint "(status::text = 'accepted'::text) = (accepted_at IS NOT NULL)", name: "followings_accepted_timestamp"
    t.check_constraint "(status::text = 'undone'::text) = (undone_at IS NOT NULL)", name: "followings_undone_timestamp"
    t.check_constraint "follower_actor_id <> followed_actor_id", name: "followings_no_self_follow"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'accepted'::character varying::text, 'rejected'::character varying::text, 'undone'::character varying::text])", name: "followings_status"
  end

  create_table "funding_contributions", force: :cascade do |t|
    t.bigint "user_id"
    t.string "provider", null: false
    t.string "tier", null: false
    t.string "external_id", null: false
    t.datetime "paid_at", null: false
    t.datetime "expires_at", null: false
    t.string "status", default: "active", null: false
    t.bigint "amount_cents"
    t.string "currency", limit: 3
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "funding_subscription_id"
    t.datetime "starts_at", null: false
    t.index ["funding_subscription_id"], name: "index_funding_contributions_on_funding_subscription_id"
    t.index ["provider", "external_id"], name: "index_funding_contributions_on_provider_and_external_id", unique: true
    t.index ["user_id", "status", "expires_at"], name: "index_funding_contributions_on_current_badges"
    t.index ["user_id"], name: "index_funding_contributions_on_user_id"
    t.check_constraint "amount_cents IS NULL OR amount_cents >= 0", name: "funding_contributions_amount_nonnegative"
    t.check_constraint "currency IS NULL OR currency::text ~ '\\A[A-Z]{3}\\Z'::text", name: "funding_contributions_currency_format"
    t.check_constraint "expires_at > starts_at", name: "funding_contributions_period"
    t.check_constraint "jsonb_typeof(metadata) = 'object'::text", name: "funding_contributions_metadata_object"
    t.check_constraint "length(btrim(external_id::text)) > 0", name: "funding_contributions_external_id_present"
    t.check_constraint "provider::text <> 'manual'::text OR funding_subscription_id IS NULL", name: "funding_contributions_manual_subscription"
    t.check_constraint "provider::text ~ '\\A[a-z0-9_]+\\Z'::text", name: "funding_contributions_provider_format"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'revoked'::character varying::text])", name: "funding_contributions_status"
    t.check_constraint "tier::text = ANY (ARRAY['coffee'::character varying::text, 'beer'::character varying::text, 'energy'::character varying::text])", name: "funding_contributions_tier"
  end

  create_table "funding_reversals", force: :cascade do |t|
    t.bigint "funding_contribution_id", null: false
    t.string "provider", null: false
    t.string "external_id", null: false
    t.string "kind", null: false
    t.string "status", null: false
    t.bigint "amount_cents"
    t.string "currency", limit: 3
    t.datetime "reported_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["funding_contribution_id"], name: "index_funding_reversals_on_funding_contribution_id"
    t.index ["provider", "external_id"], name: "index_funding_reversals_on_provider_and_external_id", unique: true
    t.check_constraint "amount_cents IS NULL OR amount_cents >= 0", name: "funding_reversals_amount_nonnegative"
    t.check_constraint "currency IS NULL OR currency::text ~ '\\A[A-Z]{3}\\Z'::text", name: "funding_reversals_currency_format"
    t.check_constraint "kind::text = ANY (ARRAY['refund'::character varying::text, 'dispute'::character varying::text])", name: "funding_reversals_kind"
    t.check_constraint "length(btrim(external_id::text)) > 0", name: "funding_reversals_external_id_present"
    t.check_constraint "provider::text ~ '\\A[a-z0-9_]+\\Z'::text", name: "funding_reversals_provider_format"
    t.check_constraint "status::text = ANY (ARRAY['succeeded'::character varying::text, 'failed'::character varying::text, 'open'::character varying::text, 'won'::character varying::text, 'lost'::character varying::text])", name: "funding_reversals_status"
  end

  create_table "funding_subscriptions", force: :cascade do |t|
    t.bigint "user_id"
    t.string "provider", null: false
    t.string "external_id", null: false
    t.string "customer_id", null: false
    t.string "tier", null: false
    t.string "status", default: "incomplete", null: false
    t.boolean "cancel_at_period_end", default: false, null: false
    t.datetime "canceled_at"
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "external_id"], name: "index_funding_subscriptions_on_provider_and_external_id", unique: true
    t.index ["user_id"], name: "index_funding_subscriptions_on_user_id"
    t.check_constraint "length(btrim(external_id::text)) > 0 AND length(btrim(customer_id::text)) > 0", name: "funding_subscriptions_identifiers"
    t.check_constraint "provider::text ~ '^[a-z0-9_]+$'::text AND provider::text <> 'manual'::text", name: "funding_subscriptions_provider"
    t.check_constraint "status::text = ANY (ARRAY['incomplete'::character varying::text, 'active'::character varying::text, 'past_due'::character varying::text, 'paused'::character varying::text, 'canceled'::character varying::text])", name: "funding_subscriptions_status"
    t.check_constraint "tier::text = ANY (ARRAY['coffee'::character varying::text, 'beer'::character varying::text, 'energy'::character varying::text])", name: "funding_subscriptions_tier"
  end

  create_table "identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.boolean "email_verified", default: false, null: false
    t.string "issuer", null: false
    t.datetime "last_used_at"
    t.datetime "linked_at", null: false
    t.string "provider", null: false
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["issuer", "subject"], name: "index_identities_on_issuer_and_subject", unique: true
    t.index ["user_id", "provider"], name: "index_identities_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_identities_on_user_id"
    t.check_constraint "char_length(issuer::text) > 0 AND char_length(subject::text) > 0", name: "identities_issuer_subject"
    t.check_constraint "provider::text = ANY (ARRAY['google'::character varying::text, 'apple'::character varying::text, 'oidc'::character varying::text])", name: "identities_provider"
  end

  create_table "import_connections", force: :cascade do |t|
    t.boolean "auto_sync", default: true, null: false
    t.datetime "created_at", null: false
    t.text "credentials"
    t.string "external_account_id"
    t.string "external_account_name"
    t.bigint "fallback_sport_id"
    t.text "last_sync_error"
    t.datetime "last_synced_at"
    t.datetime "linked_at"
    t.datetime "pending_expires_at"
    t.string "provider", null: false
    t.string "region", default: "com", null: false
    t.datetime "revoked_at"
    t.string "status", default: "unlinked", null: false
    t.boolean "sync_equipment", default: false, null: false
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.boolean "positioned_only", default: false, null: false
    t.index ["fallback_sport_id"], name: "index_import_connections_on_fallback_sport_id"
    t.index ["provider", "status"], name: "index_import_connections_on_provider_and_status"
    t.index ["user_id", "provider"], name: "index_import_connections_on_user_id_and_provider", unique: true
    t.check_constraint "(status::text <> ALL (ARRAY['pending'::character varying::text, 'mfa_pending'::character varying::text])) OR pending_expires_at IS NOT NULL", name: "import_connections_pending_expiry"
    t.check_constraint "provider::text = ANY (ARRAY['garmin_connect'::character varying::text, 'exr'::character varying::text, 'withings'::character varying::text, 'zwift'::character varying::text])", name: "import_connections_provider"
    t.check_constraint "region::text = ANY (ARRAY['com'::character varying::text, 'cn'::character varying::text])", name: "import_connections_region"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'mfa_pending'::character varying::text, 'linked'::character varying::text, 'expired'::character varying::text, 'revoked'::character varying::text, 'unlinking'::character varying::text, 'unlinked'::character varying::text])", name: "import_connections_status"
  end

  create_table "laps", force: :cascade do |t|
    t.decimal "ascent", precision: 12, scale: 2
    t.integer "average_cadence"
    t.integer "average_heart_rate"
    t.integer "average_pace"
    t.integer "average_power"
    t.decimal "average_speed", precision: 10, scale: 4
    t.datetime "created_at", null: false
    t.decimal "descent", precision: 12, scale: 2
    t.decimal "distance", precision: 14, scale: 3
    t.integer "elapsed_time", null: false
    t.string "lap_trigger"
    t.integer "max_heart_rate"
    t.decimal "max_speed", precision: 10, scale: 4
    t.integer "moving_time", null: false
    t.integer "number", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "workout_id", null: false
    t.index ["workout_id", "number"], name: "index_laps_on_workout_id_and_number", unique: true
    t.check_constraint "(average_pace IS NULL OR average_pace >= 0) AND (average_heart_rate IS NULL OR average_heart_rate >= 0) AND (max_heart_rate IS NULL OR max_heart_rate >= 0) AND (average_cadence IS NULL OR average_cadence >= 0) AND (average_power IS NULL OR average_power >= 0)", name: "laps_physiological_metrics"
    t.check_constraint "(distance IS NULL OR distance >= 0::numeric) AND (ascent IS NULL OR ascent >= 0::numeric) AND (descent IS NULL OR descent >= 0::numeric) AND (average_speed IS NULL OR average_speed >= 0::numeric) AND (max_speed IS NULL OR max_speed >= 0::numeric)", name: "laps_non_negative_metrics"
    t.check_constraint "elapsed_time >= 0", name: "laps_elapsed_time"
    t.check_constraint "moving_time >= 0 AND moving_time <= elapsed_time", name: "laps_moving_time"
    t.check_constraint "number >= 1", name: "laps_number"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "read_at"
    t.bigint "subject_id"
    t.string "subject_type"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["subject_type", "subject_id"], name: "index_notifications_on_subject_type_and_subject_id"
    t.index ["user_id", "created_at"], name: "index_notifications_on_user_id_and_created_at"
    t.index ["user_id", "kind", "subject_type", "subject_id"], name: "index_notifications_on_user_kind_subject", unique: true, where: "(subject_id IS NOT NULL)"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.check_constraint "jsonb_typeof(payload) = 'object'::text", name: "notifications_payload_object"
    t.check_constraint "kind::text = ANY (ARRAY['follow_request'::character varying::text, 'follow_accepted'::character varying::text, 'publication_activated'::character varying::text, 'reaction'::character varying::text, 'participation_requested'::character varying::text, 'participation_suggested'::character varying::text, 'participation_confirmed'::character varying::text, 'participation_source_deleted'::character varying::text, 'comment'::character varying::text, 'import_connection_expired'::character varying::text, 'import_connection_revoked'::character varying::text, 'auto_published'::character varying::text, 'auto_publication_failed'::character varying::text, 'webhook_disabled'::character varying::text, 'participation_link_suggested'::character varying::text, 'account_export_ready'::character varying::text, 'funding_recorded'::character varying::text])", name: "notifications_kind"
  end

  create_table "people_suggestion_dismissals", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "actor_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_people_suggestion_dismissals_on_actor_id"
    t.index ["user_id", "actor_id"], name: "index_people_suggestion_dismissals_on_user_id_and_actor_id", unique: true
    t.index ["user_id"], name: "index_people_suggestion_dismissals_on_user_id"
  end

  create_table "privacy_zones", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.geography "center", limit: {srid: 4326, type: "st_point", geographic: true}, null: false
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "radius_meters", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["center"], name: "index_privacy_zones_on_center", using: :gist
    t.index ["user_id", "active"], name: "index_privacy_zones_on_user_and_active"
    t.check_constraint "char_length(name::text) <= 120", name: "privacy_zones_name_length"
    t.check_constraint "radius_meters >= 1 AND radius_meters <= 10000", name: "privacy_zones_radius_meters"
    t.check_constraint "st_srid(center::geometry) = 4326 AND st_geometrytype(center::geometry) = 'ST_Point'::text AND st_x(center::geometry) >= '-180'::integer::double precision AND st_x(center::geometry) <= 180::double precision AND st_y(center::geometry) >= '-90'::integer::double precision AND st_y(center::geometry) <= 90::double precision", name: "privacy_zones_center"
  end

  create_table "publishing_profiles", force: :cascade do |t|
    t.string "audience", null: false
    t.boolean "auto_publish", default: false, null: false
    t.boolean "auto_publish_exclude_commute", default: false, null: false
    t.string "built_in_key"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "publish_delay_seconds", default: 0, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.string "auto_publish_excluded_sports", default: [], null: false, array: true
    t.index ["user_id", "audience"], name: "index_publishing_profiles_on_user_audience_auto", unique: true, where: "auto_publish"
    t.index ["user_id", "built_in_key"], name: "index_publishing_profiles_on_user_and_built_in_key", unique: true, where: "(built_in_key IS NOT NULL)"
    t.index ["user_id", "position"], name: "index_publishing_profiles_on_user_and_position"
    t.index ["uuid"], name: "index_publishing_profiles_on_uuid", unique: true
    t.check_constraint "\"position\" >= 0", name: "publishing_profiles_position"
    t.check_constraint "audience::text = ANY (ARRAY['public'::character varying::text, 'followers'::character varying::text])", name: "publishing_profiles_audience"
    t.check_constraint "built_in_key IS NULL OR (built_in_key::text = ANY (ARRAY['public'::character varying::text, 'followers'::character varying::text])) AND built_in_key::text = audience::text", name: "publishing_profiles_built_in_key"
    t.check_constraint "char_length(name::text) >= 1 AND char_length(name::text) <= 120", name: "publishing_profiles_name_length"
    t.check_constraint "jsonb_typeof(settings) = 'object'::text", name: "publishing_profiles_settings_object"
    t.check_constraint "publish_delay_seconds = ANY (ARRAY[0, 86400, 259200, 604800, 1209600, 2592000])", name: "publishing_profiles_publish_delay_seconds"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.text "auth", null: false
    t.datetime "created_at", null: false
    t.text "endpoint", null: false
    t.string "endpoint_digest", null: false
    t.integer "failure_count", default: 0, null: false
    t.boolean "hide_content", default: false, null: false
    t.datetime "last_success_at"
    t.string "p256dh", null: false
    t.bigint "session_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["endpoint_digest"], name: "index_push_subscriptions_on_endpoint_digest", unique: true
    t.index ["session_id"], name: "index_push_subscriptions_on_session_id", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
    t.check_constraint "char_length(endpoint_digest::text) = 64", name: "push_subscriptions_endpoint_digest"
    t.check_constraint "failure_count >= 0", name: "push_subscriptions_failure_count"
  end

  create_table "reactions", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", default: "like", null: false
    t.bigint "remote_note_id"
    t.datetime "undone_at"
    t.datetime "updated_at", null: false
    t.text "uri", null: false
    t.bigint "workout_id"
    t.string "audience", null: false
    t.index ["actor_id", "remote_note_id"], name: "index_active_reactions_on_actor_and_remote_note", unique: true, where: "((undone_at IS NULL) AND (remote_note_id IS NOT NULL))"
    t.index ["actor_id", "workout_id"], name: "index_active_reactions_on_actor_and_workout", unique: true, where: "(undone_at IS NULL)"
    t.index ["actor_id"], name: "index_reactions_on_actor_id"
    t.index ["uri"], name: "index_reactions_on_uri", unique: true
    t.index ["workout_id"], name: "index_reactions_on_workout_id"
    t.check_constraint "((workout_id IS NOT NULL)::integer + (remote_note_id IS NOT NULL)::integer) = 1", name: "reactions_single_target"
    t.check_constraint "audience::text = ANY (ARRAY['public'::character varying::text, 'followers'::character varying::text])", name: "reactions_audience"
    t.check_constraint "kind::text = ANY (ARRAY['beer'::character varying::text, 'energy'::character varying::text, 'coffee'::character varying::text, 'like'::character varying::text])", name: "reactions_kind"
  end

  create_table "records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "record_type", null: false
    t.bigint "sport_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.decimal "value", precision: 20, scale: 6, null: false
    t.bigint "workout_id"
    t.datetime "workout_started_at", null: false
    t.index ["user_id", "sport_id", "record_type"], name: "index_records_on_user_sport_type", unique: true
    t.index ["workout_id", "record_type"], name: "index_records_on_workout_type"
    t.check_constraint "record_type::text = ANY (ARRAY['AP'::character varying::text, 'AS'::character varying::text, 'BP'::character varying::text, 'FD'::character varying::text, 'HA'::character varying::text, 'LD'::character varying::text, 'MS'::character varying::text, 'MC'::character varying::text])", name: "records_record_type"
    t.check_constraint "value >= 0::numeric", name: "records_value"
  end

  create_table "recovery_codes", force: :cascade do |t|
    t.string "code_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "used_at"
    t.bigint "user_id", null: false
    t.index ["code_digest"], name: "index_recovery_codes_on_code_digest", unique: true
    t.index ["user_id"], name: "index_recovery_codes_on_user_id"
  end

  create_table "registration_invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email_address", null: false
    t.datetime "expires_at", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_registration_invitations_on_email_address"
    t.index ["token_digest"], name: "index_registration_invitations_on_token_digest", unique: true
    t.check_constraint "char_length(display_name::text) <= 60", name: "registration_invitations_display_name_length"
  end

  create_table "remote_note_attachments", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.bigint "blob_id"
    t.integer "byte_size"
    t.string "content_digest"
    t.datetime "created_at", null: false
    t.datetime "fetched_at"
    t.string "kind", null: false
    t.text "last_error"
    t.string "media_type"
    t.datetime "next_attempt_at"
    t.datetime "purged_at"
    t.bigint "remote_note_id", null: false
    t.text "remote_url", null: false
    t.string "status", default: "pending", null: false
    t.string "theme", default: "light", null: false
    t.datetime "updated_at", null: false
    t.index ["blob_id"], name: "index_remote_note_attachments_on_blob_id"
    t.index ["remote_note_id", "kind", "theme"], name: "index_remote_note_attachments_on_note_kind_and_theme", unique: true
    t.index ["status", "next_attempt_at"], name: "index_remote_note_attachments_on_status_and_next_attempt_at"
    t.check_constraint "attempts >= 0", name: "remote_note_attachments_attempts"
    t.check_constraint "char_length(remote_url) > 0", name: "remote_note_attachments_remote_url"
    t.check_constraint "kind::text = ANY (ARRAY['gpx'::character varying::text, 'route_image'::character varying::text])", name: "remote_note_attachments_kind"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'fetching'::character varying::text, 'cached'::character varying::text, 'failed'::character varying::text, 'unavailable'::character varying::text, 'purged'::character varying::text])", name: "remote_note_attachments_status"
    t.check_constraint "theme::text = ANY (ARRAY['light'::character varying::text, 'dark'::character varying::text])", name: "remote_note_attachments_theme"
  end

  create_table "remote_note_recipients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "inbox_item_id"
    t.bigint "recipient_actor_id", null: false
    t.bigint "remote_note_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.string "withdrawal_reason"
    t.datetime "withdrawn_at"
    t.index ["recipient_actor_id", "status", "remote_note_id"], name: "index_remote_note_recipients_on_recipient_and_status"
    t.index ["remote_note_id", "recipient_actor_id"], name: "index_remote_note_recipients_on_note_and_actor", unique: true
    t.index ["remote_note_id"], name: "index_remote_note_recipients_on_remote_note_id"
    t.check_constraint "(status::text = 'withdrawn'::text) = (withdrawn_at IS NOT NULL)", name: "remote_note_recipients_withdrawal_state"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'withdrawn'::character varying::text])", name: "remote_note_recipients_status"
    t.check_constraint "withdrawal_reason IS NULL OR (withdrawal_reason::text = ANY (ARRAY['unfollow'::character varying::text, 'rejected'::character varying::text, 'blocked'::character varying::text, 'deleted'::character varying::text, 'unreachable'::character varying::text]))", name: "remote_note_recipients_withdrawal_reason"
  end

  create_table "remote_notes", force: :cascade do |t|
    t.text "activity_uri", null: false
    t.bigint "actor_id", null: false
    t.string "audience", default: "public", null: false
    t.text "content_html"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.datetime "location_data_purged_at"
    t.jsonb "metrics", default: {}, null: false
    t.text "object_uri", null: false
    t.datetime "published_at"
    t.jsonb "raw", default: {}, null: false
    t.datetime "received_at", null: false
    t.jsonb "representation", default: {}, null: false
    t.jsonb "route_metadata", default: {}, null: false
    t.string "source_domain", null: false
    t.string "sport_label"
    t.datetime "started_at"
    t.string "status", default: "active", null: false
    t.text "title"
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.jsonb "warnings", default: [], null: false
    t.index ["actor_id", "published_at"], name: "index_remote_notes_on_actor_id_and_published_at"
    t.index ["object_uri"], name: "index_remote_notes_on_object_uri", unique: true
    t.index ["source_domain", "status"], name: "index_remote_notes_on_source_domain_and_status"
    t.index ["status", "published_at"], name: "index_remote_notes_on_status_and_published_at"
    t.index ["status", "updated_at"], name: "index_remote_notes_on_cleanup", where: "(((status)::text = 'deleted'::text) AND (location_data_purged_at IS NULL))"
    t.index ["uuid"], name: "index_remote_notes_on_uuid", unique: true
    t.check_constraint "(status::text = 'deleted'::text) = (deleted_at IS NOT NULL)", name: "remote_notes_deletion_state"
    t.check_constraint "audience::text = ANY (ARRAY['public'::character varying::text, 'followers'::character varying::text])", name: "remote_notes_audience"
    t.check_constraint "char_length(object_uri) > 0 AND char_length(activity_uri) > 0", name: "remote_notes_uris"
    t.check_constraint "char_length(source_domain::text) > 0", name: "remote_notes_source_domain"
    t.check_constraint "jsonb_typeof(metrics) = 'object'::text", name: "remote_notes_metrics_object"
    t.check_constraint "jsonb_typeof(raw) = 'object'::text", name: "remote_notes_raw_object"
    t.check_constraint "jsonb_typeof(representation) = 'object'::text", name: "remote_notes_representation_object"
    t.check_constraint "jsonb_typeof(route_metadata) = 'object'::text", name: "remote_notes_route_metadata_object"
    t.check_constraint "jsonb_typeof(warnings) = 'array'::text", name: "remote_notes_warnings_array"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'deleted'::character varying::text])", name: "remote_notes_status"
  end

  create_table "remote_participations", force: :cascade do |t|
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "declined_at"
    t.text "invite_activity_uri", null: false
    t.text "object_uri", null: false
    t.bigint "recipient_actor_id", null: false
    t.bigint "remote_note_id", null: false
    t.string "sport_slug", limit: 64
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "withdrawn_at"
    t.index ["invite_activity_uri"], name: "index_remote_participations_on_invite_activity_uri", unique: true
    t.index ["recipient_actor_id", "object_uri"], name: "index_remote_participations_live_pair", unique: true, where: "(withdrawn_at IS NULL)"
    t.index ["recipient_actor_id"], name: "index_remote_participations_on_recipient_actor_id"
    t.index ["remote_note_id"], name: "index_remote_participations_on_remote_note_id"
    t.index ["uuid"], name: "index_remote_participations_on_uuid", unique: true
    t.check_constraint "NOT (confirmed_at IS NOT NULL AND declined_at IS NOT NULL)", name: "remote_participations_one_answer"
  end

  create_table "remote_segment_attachments", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.bigint "blob_id"
    t.integer "byte_size"
    t.string "content_digest"
    t.datetime "created_at", null: false
    t.datetime "fetched_at"
    t.string "kind", null: false
    t.text "last_error"
    t.string "media_type"
    t.datetime "next_attempt_at"
    t.datetime "purged_at"
    t.bigint "remote_segment_id", null: false
    t.text "remote_url", null: false
    t.string "status", default: "pending", null: false
    t.string "theme", default: "light", null: false
    t.datetime "updated_at", null: false
    t.index ["blob_id"], name: "index_remote_segment_attachments_on_blob_id"
    t.index ["remote_segment_id", "kind", "theme"], name: "index_remote_segment_attachments_on_segment_kind_and_theme", unique: true
    t.index ["status", "next_attempt_at"], name: "index_remote_segment_attachments_on_status_and_next_attempt_at"
    t.check_constraint "attempts >= 0", name: "remote_segment_attachments_attempts"
    t.check_constraint "char_length(remote_url) > 0", name: "remote_segment_attachments_remote_url"
    t.check_constraint "kind::text = ANY (ARRAY['gpx'::character varying::text, 'route_image'::character varying::text])", name: "remote_segment_attachments_kind"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'fetching'::character varying::text, 'cached'::character varying::text, 'failed'::character varying::text, 'unavailable'::character varying::text, 'purged'::character varying::text])", name: "remote_segment_attachments_status"
    t.check_constraint "theme::text = ANY (ARRAY['light'::character varying::text, 'dark'::character varying::text])", name: "remote_segment_attachments_theme"
  end

  create_table "remote_segment_recipients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "inbox_item_id"
    t.bigint "recipient_actor_id", null: false
    t.bigint "remote_segment_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.string "withdrawal_reason"
    t.datetime "withdrawn_at"
    t.index ["recipient_actor_id", "status", "remote_segment_id"], name: "index_remote_segment_recipients_on_recipient_and_status"
    t.index ["remote_segment_id", "recipient_actor_id"], name: "index_remote_segment_recipients_on_segment_and_actor", unique: true
    t.index ["remote_segment_id"], name: "index_remote_segment_recipients_on_remote_segment_id"
    t.check_constraint "(status::text = 'withdrawn'::text) = (withdrawn_at IS NOT NULL)", name: "remote_segment_recipients_withdrawal_state"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'withdrawn'::character varying::text])", name: "remote_segment_recipients_status"
    t.check_constraint "withdrawal_reason IS NULL OR (withdrawal_reason::text = ANY (ARRAY['unfollow'::character varying::text, 'rejected'::character varying::text, 'blocked'::character varying::text, 'deleted'::character varying::text, 'unreachable'::character varying::text]))", name: "remote_segment_recipients_withdrawal_reason"
  end

  create_table "remote_segments", force: :cascade do |t|
    t.text "activity_uri", null: false
    t.bigint "actor_id", null: false
    t.decimal "ascent", precision: 12, scale: 2
    t.string "audience", default: "public", null: false
    t.decimal "average_grade", precision: 5, scale: 2
    t.text "content_html"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.decimal "descent", precision: 12, scale: 2
    t.text "description"
    t.decimal "distance", precision: 14, scale: 3
    t.string "kind", default: "segment", null: false
    t.datetime "location_data_purged_at"
    t.string "name", null: false
    t.text "object_uri", null: false
    t.datetime "published_at", null: false
    t.jsonb "raw", default: {}, null: false
    t.datetime "received_at", null: false
    t.jsonb "representation", default: {}, null: false
    t.jsonb "route_metadata", default: {}, null: false
    t.string "source_domain", null: false
    t.string "sport_label"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.jsonb "warnings", default: [], null: false
    t.index ["actor_id", "published_at"], name: "index_remote_segments_on_actor_id_and_published_at"
    t.index ["object_uri"], name: "index_remote_segments_on_object_uri", unique: true
    t.index ["source_domain", "status"], name: "index_remote_segments_on_source_domain_and_status"
    t.index ["status", "published_at"], name: "index_remote_segments_on_status_and_published_at"
    t.index ["status", "updated_at"], name: "index_remote_segments_on_cleanup", where: "(((status)::text = 'deleted'::text) AND (location_data_purged_at IS NULL))"
    t.check_constraint "(ascent IS NULL OR ascent >= 0::numeric) AND (descent IS NULL OR descent >= 0::numeric)", name: "remote_segments_elevation"
    t.check_constraint "(status::text = 'deleted'::text) = (deleted_at IS NOT NULL)", name: "remote_segments_deletion_state"
    t.check_constraint "audience::text = ANY (ARRAY['public'::character varying::text, 'followers'::character varying::text])", name: "remote_segments_audience"
    t.check_constraint "average_grade IS NULL OR average_grade >= '-100'::integer::numeric AND average_grade <= 100::numeric", name: "remote_segments_average_grade"
    t.check_constraint "char_length(name::text) <= 120", name: "remote_segments_name_length"
    t.check_constraint "char_length(object_uri) > 0 AND char_length(activity_uri) > 0", name: "remote_segments_uris"
    t.check_constraint "char_length(source_domain::text) > 0", name: "remote_segments_source_domain"
    t.check_constraint "distance IS NULL OR distance > 0::numeric", name: "remote_segments_distance"
    t.check_constraint "jsonb_typeof(raw) = 'object'::text", name: "remote_segments_raw_object"
    t.check_constraint "jsonb_typeof(representation) = 'object'::text", name: "remote_segments_representation_object"
    t.check_constraint "jsonb_typeof(route_metadata) = 'object'::text", name: "remote_segments_route_metadata_object"
    t.check_constraint "jsonb_typeof(warnings) = 'array'::text", name: "remote_segments_warnings_array"
    t.check_constraint "kind::text = 'segment'::text", name: "remote_segments_kind"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'deleted'::character varying::text])", name: "remote_segments_status"
  end

  create_table "route_suggestion_workouts", force: :cascade do |t|
    t.bigint "route_suggestion_id", null: false
    t.bigint "workout_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["route_suggestion_id", "workout_id"], name: "idx_on_route_suggestion_id_workout_id_35b9f80f0b", unique: true
    t.index ["workout_id"], name: "index_route_suggestion_workouts_on_workout_id", unique: true
  end

  create_table "route_suggestions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "sport_id", null: false
    t.bigint "reference_workout_id"
    t.bigint "segment_id"
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reference_workout_id"], name: "index_route_suggestions_on_reference_workout_id"
    t.index ["segment_id"], name: "index_route_suggestions_on_segment_id"
    t.index ["sport_id"], name: "index_route_suggestions_on_sport_id"
    t.index ["user_id", "status"], name: "index_route_suggestions_on_user_id_and_status"
    t.index ["user_id"], name: "index_route_suggestions_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'dismissed'::character varying::text, 'accepted'::character varying::text])", name: "route_suggestions_status"
  end

  create_table "segment_efforts", force: :cascade do |t|
    t.boolean "anonymous", default: false, null: false
    t.decimal "ascent", precision: 12, scale: 2
    t.integer "average_cadence"
    t.integer "average_heart_rate"
    t.integer "average_pace"
    t.integer "average_power"
    t.decimal "average_speed", precision: 10, scale: 4, null: false
    t.datetime "created_at", null: false
    t.decimal "descent", precision: 12, scale: 2
    t.decimal "deviation_meters", precision: 6, scale: 2, null: false
    t.decimal "distance", precision: 14, scale: 3, null: false
    t.integer "elapsed_time", null: false
    t.integer "end_point_index", null: false
    t.integer "grade_adjusted_pace"
    t.integer "matcher_version", null: false
    t.integer "max_heart_rate"
    t.integer "max_power"
    t.integer "moving_time", null: false
    t.integer "occurrence_index", null: false
    t.boolean "personal_best", default: false, null: false
    t.bigint "segment_id", null: false
    t.bigint "sport_id", null: false
    t.decimal "start_offset_meters", precision: 14, scale: 3, null: false
    t.integer "start_point_index", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.bigint "workout_id", null: false
    t.index ["segment_id", "elapsed_time"], name: "index_segment_efforts_on_segment_id_and_elapsed_time"
    t.index ["segment_id", "sport_id", "elapsed_time"], name: "index_segment_efforts_on_segment_sport_elapsed_time"
    t.index ["segment_id", "user_id", "sport_id"], name: "index_segment_efforts_on_segment_user_sport_personal_best", where: "personal_best"
    t.index ["segment_id", "workout_id", "occurrence_index"], name: "idx_on_segment_id_workout_id_occurrence_index_7908bf19ed", unique: true
    t.index ["user_id", "segment_id", "elapsed_time"], name: "idx_on_user_id_segment_id_elapsed_time_c1f7831492"
    t.index ["uuid"], name: "index_segment_efforts_on_uuid", unique: true
    t.index ["workout_id"], name: "index_segment_efforts_on_workout_id"
    t.check_constraint "(average_pace IS NULL OR average_pace >= 0) AND (average_heart_rate IS NULL OR average_heart_rate >= 0) AND (max_heart_rate IS NULL OR max_heart_rate >= 0) AND (average_cadence IS NULL OR average_cadence >= 0) AND (average_power IS NULL OR average_power >= 0) AND (max_power IS NULL OR max_power >= 0)", name: "segment_efforts_physiological_metrics"
    t.check_constraint "distance >= 0::numeric AND (ascent IS NULL OR ascent >= 0::numeric) AND (descent IS NULL OR descent >= 0::numeric) AND average_speed >= 0::numeric", name: "segment_efforts_non_negative_metrics"
    t.check_constraint "elapsed_time > 0", name: "segment_efforts_elapsed_time"
    t.check_constraint "end_point_index > start_point_index", name: "segment_efforts_point_indexes"
    t.check_constraint "grade_adjusted_pace IS NULL OR grade_adjusted_pace >= 0", name: "segment_efforts_grade_adjusted_pace"
    t.check_constraint "moving_time >= 0 AND moving_time <= elapsed_time", name: "segment_efforts_moving_time"
    t.check_constraint "occurrence_index >= 0", name: "segment_efforts_occurrence_index"
    t.check_constraint "start_offset_meters >= 0::numeric AND deviation_meters >= 0::numeric", name: "segment_efforts_geometry_metrics"
  end

  create_table "segment_opt_outs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "segment_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["segment_id", "user_id"], name: "index_segment_opt_outs_on_segment_id_and_user_id", unique: true
    t.index ["segment_id"], name: "index_segment_opt_outs_on_segment_id"
    t.index ["user_id"], name: "index_segment_opt_outs_on_user_id"
  end

  create_table "segment_publications", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.string "audience", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "location_data_purged_at"
    t.text "object_uri", null: false
    t.datetime "published_at", null: false
    t.jsonb "representation", default: {}, null: false
    t.jsonb "route_metadata", default: {}, null: false
    t.bigint "sanitized_gpx_blob_id"
    t.bigint "sanitized_route_image_blob_id"
    t.bigint "sanitized_route_image_dark_blob_id"
    t.bigint "segment_id"
    t.string "source_fingerprint", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["actor_id"], name: "index_segment_publications_on_actor_id"
    t.index ["object_uri"], name: "index_segment_publications_on_object_uri", unique: true
    t.index ["sanitized_gpx_blob_id"], name: "index_segment_publications_on_sanitized_gpx_blob_id"
    t.index ["sanitized_route_image_blob_id"], name: "index_segment_publications_on_sanitized_route_image_blob_id"
    t.index ["sanitized_route_image_dark_blob_id"], name: "idx_on_sanitized_route_image_dark_blob_id_69ac1cf182"
    t.index ["segment_id", "status"], name: "index_segment_publications_on_segment_id_and_status"
    t.index ["segment_id"], name: "index_active_segment_publications_on_segment_id", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["updated_at"], name: "index_segment_publications_on_cleanup", where: "(((status)::text = 'deleted'::text) AND (location_data_purged_at IS NULL))"
    t.index ["uuid"], name: "index_segment_publications_on_uuid", unique: true
    t.check_constraint "audience::text = ANY (ARRAY['public'::character varying::text, 'followers'::character varying::text])", name: "segment_publications_audience"
    t.check_constraint "char_length(object_uri) > 0", name: "segment_publications_object_uri"
    t.check_constraint "jsonb_typeof(representation) = 'object'::text", name: "segment_publications_representation_object"
    t.check_constraint "jsonb_typeof(route_metadata) = 'object'::text", name: "segment_publications_route_metadata_object"
    t.check_constraint "source_fingerprint::text ~ '^[0-9a-f]{64}$'::text", name: "segment_publications_source_fingerprint"
    t.check_constraint "status::text = 'active'::text AND deleted_at IS NULL OR status::text = 'deleted'::text AND deleted_at IS NOT NULL", name: "segment_publications_deletion_state"
    t.check_constraint "status::text = 'deleted'::text OR segment_id IS NOT NULL", name: "segment_publications_active_requires_source"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'deleted'::character varying::text])", name: "segment_publications_status"
  end

  create_table "segments", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.decimal "ascent", precision: 12, scale: 2
    t.integer "athletes_count", default: 0, null: false
    t.decimal "average_grade", precision: 5, scale: 2
    t.float "bounds", null: false, array: true
    t.datetime "created_at", null: false
    t.decimal "descent", precision: 12, scale: 2
    t.text "description"
    t.decimal "distance", precision: 14, scale: 3, null: false
    t.integer "efforts_count", default: 0, null: false
    t.jsonb "elevation_profile"
    t.geography "end_point", limit: {srid: 4326, type: "st_point", geographic: true}, null: false
    t.geography "geom", limit: {srid: 4326, type: "line_string", geographic: true}, null: false
    t.string "kind", null: false
    t.integer "match_tolerance_meters", default: 25, null: false
    t.integer "matcher_version", null: false
    t.decimal "max_elevation", precision: 10, scale: 2
    t.decimal "min_elevation", precision: 10, scale: 2
    t.string "name", null: false
    t.datetime "place_geocoded_at"
    t.string "place_name", limit: 120
    t.string "place_status", default: "pending", null: false
    t.datetime "privacy_zone_acknowledged_at"
    t.bigint "remote_segment_id"
    t.integer "route_image_version", default: 0, null: false
    t.float "signature", limit: 24, null: false, array: true
    t.integer "source_end_index"
    t.integer "source_start_index"
    t.bigint "source_workout_id"
    t.bigint "sport_id"
    t.geography "start_point", limit: {srid: 4326, type: "st_point", geographic: true}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.string "visibility", default: "private", null: false
    t.string "elevation_source", default: "device", null: false
    t.string "elevation_status"
    t.datetime "renamed_at"
    t.index ["end_point"], name: "index_segments_on_end_point", using: :gist
    t.index ["geom"], name: "index_segments_on_geom", using: :gist
    t.index ["place_status", "id"], name: "index_segments_on_place_status_and_id"
    t.index ["remote_segment_id", "user_id"], name: "index_segments_on_remote_segment_id_and_user_id", unique: true, where: "(remote_segment_id IS NOT NULL)"
    t.index ["route_image_version", "id"], name: "index_segments_on_route_image_version_and_id"
    t.index ["start_point"], name: "index_segments_on_start_point", using: :gist
    t.index ["user_id", "kind"], name: "index_segments_on_user_id_and_kind"
    t.index ["uuid"], name: "index_segments_on_uuid", unique: true
    t.index ["visibility", "kind"], name: "index_segments_on_visibility_and_kind"
    t.check_constraint "ascent IS NULL OR ascent >= 0::numeric", name: "segments_ascent"
    t.check_constraint "cardinality(bounds) = 4", name: "segments_bounds"
    t.check_constraint "cardinality(signature) = 64", name: "segments_signature"
    t.check_constraint "char_length(name::text) >= 1 AND char_length(name::text) <= 120", name: "segments_name_length"
    t.check_constraint "descent IS NULL OR descent >= 0::numeric", name: "segments_descent"
    t.check_constraint "description IS NULL OR char_length(description) <= 2000", name: "segments_description_length"
    t.check_constraint "distance > 0::numeric", name: "segments_distance"
    t.check_constraint "efforts_count >= 0 AND athletes_count >= 0", name: "segments_counts"
    t.check_constraint "elevation_source::text = ANY (ARRAY['device'::character varying::text, 'dem'::character varying::text])", name: "segments_elevation_source"
    t.check_constraint "elevation_status IS NULL OR (elevation_status::text = ANY (ARRAY['ready'::character varying::text, 'unavailable'::character varying::text, 'failed'::character varying::text]))", name: "segments_elevation_status"
    t.check_constraint "kind::text = ANY (ARRAY['segment'::character varying::text, 'route'::character varying::text, 'loop'::character varying::text])", name: "segments_kind"
    t.check_constraint "match_tolerance_meters >= 5 AND match_tolerance_meters <= 100", name: "segments_match_tolerance_meters"
    t.check_constraint "place_status::text = ANY (ARRAY['pending'::character varying::text, 'ready'::character varying::text, 'unavailable'::character varying::text, 'failed'::character varying::text])", name: "segments_place_status"
    t.check_constraint "route_image_version >= 0", name: "segments_route_image_version"
    t.check_constraint "st_npoints(geom::geometry) >= 2", name: "segments_geometry"
    t.check_constraint "visibility::text = ANY (ARRAY['public'::character varying::text, 'followers_only'::character varying::text, 'private'::character varying::text])", name: "segments_visibility"
  end

  create_table "session_handoffs", force: :cascade do |t|
    t.string "code_challenge", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.text "payload", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_session_handoffs_on_expires_at"
    t.index ["token_digest"], name: "index_session_handoffs_on_token_digest", unique: true
    t.check_constraint "char_length(code_challenge::text) = 43", name: "session_handoffs_code_challenge"
  end

  create_table "sessions", force: :cascade do |t|
    t.string "auth_method", default: "password", null: false
    t.datetime "created_at", null: false
    t.boolean "enrolment_only", default: false, null: false
    t.string "ip_address"
    t.datetime "last_seen_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "reauthenticated_at"
    t.datetime "second_factor_at"
    t.string "second_factor_method"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
    t.check_constraint "(second_factor_method IS NULL) = (second_factor_at IS NULL)", name: "sessions_second_factor_state"
    t.check_constraint "auth_method::text = ANY (ARRAY['password'::character varying::text, 'provider:google'::character varying::text, 'provider:apple'::character varying::text, 'provider:oidc'::character varying::text])", name: "sessions_auth_method"
    t.check_constraint "second_factor_method IS NULL OR (second_factor_method::text = ANY (ARRAY['totp'::character varying::text, 'webauthn'::character varying::text, 'recovery_code'::character varying::text]))", name: "sessions_second_factor_method"
  end

  create_table "sports", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "cadence_unit"
    t.string "colour_group", null: false
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.integer "pace_basis_metres"
    t.string "pace_speed_display", null: false
    t.integer "position", null: false
    t.boolean "records_elevation", default: true, null: false
    t.boolean "records_power", default: false, null: false
    t.string "slug", null: false
    t.decimal "stopped_speed_threshold", precision: 5, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.boolean "virtual", default: false, null: false
    t.index ["label"], name: "index_sports_on_label", unique: true
    t.index ["position"], name: "index_sports_on_position", unique: true
    t.index ["slug"], name: "index_sports_on_slug", unique: true
    t.check_constraint "\"position\" > 0", name: "sports_position"
    t.check_constraint "cadence_unit IS NULL OR (cadence_unit::text = ANY (ARRAY['rpm'::character varying::text, 'spm'::character varying::text]))", name: "sports_cadence_unit"
    t.check_constraint "colour_group::text = ANY (ARRAY['run'::character varying::text, 'ride'::character varying::text, 'hike'::character varying::text, 'swim'::character varying::text, 'ski'::character varying::text, 'other'::character varying::text])", name: "sports_colour_group"
    t.check_constraint "pace_basis_metres IS NULL OR pace_basis_metres > 0", name: "sports_pace_basis_metres"
    t.check_constraint "pace_speed_display::text = ANY (ARRAY['pace'::character varying::text, 'speed'::character varying::text, 'pace_and_speed'::character varying::text])", name: "sports_pace_speed_display"
    t.check_constraint "slug::text ~ '\\A[a-z][a-z0-9_]*\\Z'::text", name: "sports_slug_format"
    t.check_constraint "stopped_speed_threshold >= 0::numeric", name: "sports_stopped_speed_threshold"
  end

  create_table "track_segments", force: :cascade do |t|
    t.decimal "ascent", precision: 12, scale: 2, null: false
    t.integer "average_cadence"
    t.integer "average_heart_rate"
    t.integer "average_pace"
    t.integer "average_power"
    t.decimal "average_speed", precision: 10, scale: 4, null: false
    t.integer "best_pace"
    t.datetime "created_at", null: false
    t.decimal "descent", precision: 12, scale: 2, null: false
    t.decimal "distance", precision: 14, scale: 3, null: false
    t.integer "duration", null: false
    t.geography "geom", limit: {srid: 4326, type: "line_string", geographic: true}
    t.integer "grade_adjusted_pace"
    t.integer "max_cadence"
    t.decimal "max_elevation", precision: 10, scale: 2
    t.integer "max_heart_rate"
    t.integer "max_power"
    t.decimal "max_speed", precision: 10, scale: 4
    t.decimal "min_elevation", precision: 10, scale: 2
    t.integer "moving_time", null: false
    t.integer "pause_time", null: false
    t.jsonb "points", null: false
    t.integer "points_count", null: false
    t.integer "position", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "workout_id", null: false
    t.index ["geom"], name: "index_track_segments_on_geom", using: :gist
    t.index ["workout_id", "position"], name: "index_track_segments_on_workout_id_and_position", unique: true
    t.check_constraint "(average_heart_rate IS NULL OR average_heart_rate >= 0) AND (max_heart_rate IS NULL OR max_heart_rate >= 0) AND (average_cadence IS NULL OR average_cadence >= 0) AND (max_cadence IS NULL OR max_cadence >= 0) AND (average_power IS NULL OR average_power >= 0) AND (max_power IS NULL OR max_power >= 0)", name: "track_segments_physiological_metrics"
    t.check_constraint "\"position\" >= 0", name: "track_segments_position"
    t.check_constraint "average_pace IS NULL OR average_pace >= 0", name: "track_segments_average_pace"
    t.check_constraint "best_pace IS NULL OR best_pace >= 0", name: "track_segments_best_pace"
    t.check_constraint "distance >= 0::numeric AND ascent >= 0::numeric AND descent >= 0::numeric AND average_speed >= 0::numeric", name: "track_segments_non_negative_metrics"
    t.check_constraint "duration >= 0", name: "track_segments_duration"
    t.check_constraint "grade_adjusted_pace IS NULL OR grade_adjusted_pace >= 0", name: "track_segments_grade_adjusted_pace"
    t.check_constraint "max_speed IS NULL OR max_speed >= 0::numeric", name: "track_segments_max_speed"
    t.check_constraint "moving_time >= 0 AND moving_time <= duration", name: "track_segments_moving_time"
    t.check_constraint "pause_time = (duration - moving_time)", name: "track_segments_pause_time"
    t.check_constraint "points_count >= 2 AND jsonb_typeof(points) = 'array'::text AND jsonb_array_length(points) = points_count", name: "track_segments_points"
    t.check_constraint "st_npoints(geom::geometry) >= 2", name: "track_segments_geometry"
  end

  create_table "users", force: :cascade do |t|
    t.bigint "avatar_seed", null: false
    t.text "bio"
    t.datetime "created_at", null: false
    t.bigint "default_cycling_sport_id"
    t.bigint "default_running_sport_id"
    t.bigint "default_walking_sport_id"
    t.string "display_name"
    t.boolean "elevation_enrichment_enabled", default: false, null: false
    t.string "email_address", null: false
    t.boolean "gravatar_opt_in", default: false, null: false
    t.string "locale", default: "fr", null: false
    t.boolean "notify_auto_publication_failed", default: true, null: false
    t.boolean "notify_auto_published", default: true, null: false
    t.boolean "notify_comments", default: true, null: false
    t.boolean "notify_follow_accepted", default: true, null: false
    t.boolean "notify_follow_requests", default: true, null: false
    t.boolean "notify_import_connections", default: true, null: false
    t.boolean "notify_participation_confirmed", default: true, null: false
    t.boolean "notify_participation_requests", default: true, null: false
    t.boolean "notify_publication_activated", default: true, null: false
    t.boolean "notify_reactions", default: true, null: false
    t.boolean "notify_webhooks", default: true, null: false
    t.datetime "otp_enrolled_at"
    t.bigint "otp_last_used_step"
    t.text "otp_secret"
    t.string "password_digest"
    t.string "release_notes_seen_version"
    t.string "route_image_theme", default: "auto", null: false
    t.datetime "second_factor_required_since"
    t.boolean "smooth_tracks", default: false, null: false
    t.datetime "suspended_at"
    t.text "suspension_reason"
    t.string "theme", default: "light", null: false
    t.string "time_zone", default: "Europe/Paris", null: false
    t.boolean "together_detection_enabled", default: true, null: false
    t.string "track_smoothing_level", default: "medium", null: false
    t.string "unit_system", default: "metric", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.string "webauthn_id"
    t.string "week_start", default: "monday", null: false
    t.string "leaderboard_category", default: "unspecified", null: false
    t.datetime "deletion_requested_at"
    t.datetime "deletion_scheduled_at"
    t.string "deletion_requested_by"
    t.datetime "deletion_started_at"
    t.boolean "weather_enrichment_enabled", default: false, null: false
    t.integer "max_heart_rate"
    t.integer "resting_heart_rate"
    t.string "heart_rate_zone_basis", default: "max", null: false
    t.integer "heart_rate_zone_bounds", default: [60, 70, 80, 90], null: false, array: true
    t.bigint "photo_quota_bytes"
    t.boolean "funding_badge_hidden", default: false, null: false
    t.string "funding_badge_color", default: "primary", null: false
    t.string "profile_statistics_audience", default: "none", null: false
    t.string "profile_records_audience", default: "none", null: false
    t.string "discoverable", default: "none", null: false
    t.index "lower((username)::text)", name: "index_users_on_lower_username", unique: true
    t.index ["default_cycling_sport_id"], name: "index_users_on_default_cycling_sport_id"
    t.index ["default_running_sport_id"], name: "index_users_on_default_running_sport_id"
    t.index ["default_walking_sport_id"], name: "index_users_on_default_walking_sport_id"
    t.index ["deletion_scheduled_at"], name: "index_users_on_deletion_scheduled_at", where: "(deletion_scheduled_at IS NOT NULL)"
    t.index ["discoverable"], name: "index_users_on_discoverable_members", where: "((discoverable)::text = 'members'::text)"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["webauthn_id"], name: "index_users_on_webauthn_id", unique: true, where: "(webauthn_id IS NOT NULL)"
    t.check_constraint "(otp_secret IS NULL) = (otp_enrolled_at IS NULL)", name: "users_otp_enrolment"
    t.check_constraint "array_length(heart_rate_zone_bounds, 1) = 4", name: "users_heart_rate_zone_bounds"
    t.check_constraint "deletion_requested_at IS NULL AND deletion_scheduled_at IS NULL AND deletion_requested_by IS NULL OR deletion_requested_at IS NOT NULL AND deletion_scheduled_at IS NOT NULL AND (deletion_requested_by::text = ANY (ARRAY['self'::character varying::text, 'operator'::character varying::text]))", name: "users_deletion_request"
    t.check_constraint "deletion_started_at IS NULL OR deletion_scheduled_at IS NOT NULL", name: "users_deletion_started"
    t.check_constraint "discoverable::text = ANY (ARRAY['none'::character varying::text, 'members'::character varying::text])", name: "users_discoverable"
    t.check_constraint "funding_badge_color::text = ANY (ARRAY['primary'::character varying::text, 'blue'::character varying::text, 'teal'::character varying::text, 'orange'::character varying::text, 'purple'::character varying::text, 'slate'::character varying::text])", name: "users_funding_badge_color"
    t.check_constraint "heart_rate_zone_basis::text = ANY (ARRAY['max'::character varying::text, 'reserve'::character varying::text])", name: "users_heart_rate_zone_basis"
    t.check_constraint "leaderboard_category::text = ANY (ARRAY['unspecified'::character varying::text, 'women'::character varying::text, 'men'::character varying::text])", name: "users_leaderboard_category"
    t.check_constraint "max_heart_rate IS NULL OR max_heart_rate >= 100 AND max_heart_rate <= 220", name: "users_max_heart_rate"
    t.check_constraint "photo_quota_bytes IS NULL OR photo_quota_bytes >= 0", name: "users_photo_quota_bytes"
    t.check_constraint "profile_records_audience::text = ANY (ARRAY['none'::character varying::text, 'followers'::character varying::text, 'members'::character varying::text])", name: "users_profile_records_audience"
    t.check_constraint "profile_statistics_audience::text = ANY (ARRAY['none'::character varying::text, 'followers'::character varying::text, 'members'::character varying::text])", name: "users_profile_statistics_audience"
    t.check_constraint "resting_heart_rate IS NULL OR resting_heart_rate >= 25 AND resting_heart_rate <= 120 AND (max_heart_rate IS NULL OR resting_heart_rate < max_heart_rate)", name: "users_resting_heart_rate"
    t.check_constraint "route_image_theme::text = ANY (ARRAY['auto'::character varying::text, 'light'::character varying::text, 'dark'::character varying::text])", name: "users_route_image_theme"
    t.check_constraint "track_smoothing_level::text = ANY (ARRAY['light'::character varying::text, 'medium'::character varying::text, 'strong'::character varying::text])", name: "users_track_smoothing_level"
    t.check_constraint "username::text ~ '\\A[a-z0-9_]{1,30}\\Z'::text", name: "users_username_format"
    t.check_constraint "week_start::text = ANY (ARRAY['monday'::character varying::text, 'sunday'::character varying::text])", name: "users_week_start"
  end

  create_table "webauthn_credentials", force: :cascade do |t|
    t.boolean "backed_up", default: false, null: false
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.datetime "last_used_at"
    t.string "nickname", null: false
    t.text "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.string "transports", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["external_id"], name: "index_webauthn_credentials_on_external_id", unique: true
    t.index ["user_id"], name: "index_webauthn_credentials_on_user_id"
    t.check_constraint "char_length(nickname::text) >= 1 AND char_length(nickname::text) <= 60", name: "webauthn_credentials_nickname"
    t.check_constraint "sign_count >= 0", name: "webauthn_credentials_sign_count"
  end

  create_table "webhook_deliveries", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "last_attempt_at"
    t.string "last_error"
    t.integer "last_status_code"
    t.datetime "next_attempt_at"
    t.bigint "redelivery_of_id"
    t.string "status", default: "pending", null: false
    t.datetime "succeeded_at"
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.bigint "webhook_endpoint_id", null: false
    t.bigint "webhook_event_id", null: false
    t.index ["redelivery_of_id"], name: "index_webhook_deliveries_on_redelivery_of_id"
    t.index ["status", "next_attempt_at"], name: "index_webhook_deliveries_on_status_and_next_attempt_at"
    t.index ["uuid"], name: "index_webhook_deliveries_on_uuid", unique: true
    t.index ["webhook_endpoint_id", "created_at"], name: "index_webhook_deliveries_on_webhook_endpoint_id_and_created_at"
    t.index ["webhook_endpoint_id"], name: "index_webhook_deliveries_on_webhook_endpoint_id"
    t.index ["webhook_event_id"], name: "index_webhook_deliveries_on_webhook_event_id"
    t.check_constraint "attempts >= 0", name: "webhook_deliveries_attempts"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'succeeded'::character varying::text, 'failed'::character varying::text, 'abandoned'::character varying::text])", name: "webhook_deliveries_status"
  end

  create_table "webhook_endpoints", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "disabled_at"
    t.string "disabled_reason"
    t.string "events", default: [], null: false, array: true
    t.datetime "first_failure_at"
    t.text "previous_secret"
    t.datetime "previous_secret_expires_at"
    t.text "secret", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["user_id"], name: "index_webhook_endpoints_on_user_id"
    t.index ["uuid"], name: "index_webhook_endpoints_on_uuid", unique: true
    t.check_constraint "cardinality(events) > 0", name: "webhook_endpoints_events"
    t.check_constraint "char_length(url::text) >= 1 AND char_length(url::text) <= 2048", name: "webhook_endpoints_url_length"
    t.check_constraint "consecutive_failures >= 0", name: "webhook_endpoints_failures"
    t.check_constraint "description IS NULL OR char_length(description::text) <= 200", name: "webhook_endpoints_description_length"
    t.check_constraint "disabled_at IS NULL AND disabled_reason IS NULL OR disabled_at IS NOT NULL AND (disabled_reason::text = ANY (ARRAY['failing'::character varying::text, 'gone'::character varying::text, 'operator'::character varying::text]))", name: "webhook_endpoints_disabled"
  end

  create_table "webhook_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dedupe_key", null: false
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["created_at"], name: "index_webhook_events_on_created_at"
    t.index ["user_id", "dedupe_key"], name: "index_webhook_events_on_user_id_and_dedupe_key", unique: true
    t.index ["user_id"], name: "index_webhook_events_on_user_id"
    t.index ["uuid"], name: "index_webhook_events_on_uuid", unique: true
    t.check_constraint "jsonb_typeof(payload) = 'object'::text", name: "webhook_events_payload_object"
  end

  create_table "workout_auto_publications", force: :cascade do |t|
    t.string "audience", null: false
    t.datetime "created_at", null: false
    t.datetime "deadline_at", null: false
    t.text "detail"
    t.bigint "publishing_profile_id"
    t.string "reason"
    t.datetime "settled_at"
    t.string "status", default: "waiting", null: false
    t.datetime "updated_at", null: false
    t.bigint "workout_id", null: false
    t.bigint "workout_publication_id"
    t.index ["publishing_profile_id"], name: "index_workout_auto_publications_on_publishing_profile_id"
    t.index ["status", "deadline_at"], name: "index_workout_auto_publications_on_status_deadline"
    t.index ["workout_id", "audience"], name: "index_workout_auto_publications_on_workout_audience", unique: true
    t.index ["workout_publication_id"], name: "index_workout_auto_publications_on_workout_publication_id"
    t.check_constraint "(status::text = 'waiting'::text) = (settled_at IS NULL)", name: "workout_auto_publications_settled"
    t.check_constraint "audience::text = ANY (ARRAY['public'::character varying::text, 'followers'::character varying::text])", name: "workout_auto_publications_audience"
    t.check_constraint "status::text = ANY (ARRAY['waiting'::character varying::text, 'published'::character varying::text, 'skipped'::character varying::text, 'failed'::character varying::text])", name: "workout_auto_publications_status"
  end

  create_table "workout_bulk_operation_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "failure_code"
    t.integer "position", default: 0, null: false
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.bigint "workout_bulk_operation_id", null: false
    t.bigint "workout_id"
    t.index ["workout_bulk_operation_id", "position"], name: "index_workout_bulk_operation_items_on_operation_and_position", unique: true
    t.index ["workout_bulk_operation_id"], name: "index_workout_bulk_operation_items_on_operation_id"
    t.index ["workout_id"], name: "index_workout_bulk_operation_items_on_workout_id"
    t.check_constraint "\"position\" >= 0", name: "workout_bulk_operation_items_position"
    t.check_constraint "status::text = ANY (ARRAY['queued'::text, 'modified'::text, 'skipped'::text, 'failed'::text, 'cancelled'::text])", name: "workout_bulk_operation_items_status"
  end

  create_table "workout_bulk_operations", force: :cascade do |t|
    t.datetime "cancellation_requested_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "operation", null: false
    t.jsonb "parameters", default: {}, null: false
    t.datetime "started_at"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "status"], name: "index_workout_bulk_operations_on_user_id_and_status"
    t.index ["user_id"], name: "index_workout_bulk_operations_on_user_id"
    t.check_constraint "operation::text = ANY (ARRAY['sport_change'::text, 'delete'::text])", name: "workout_bulk_operations_operation"
    t.check_constraint "status::text = ANY (ARRAY['draft'::text, 'queued'::text, 'processing'::text, 'completed'::text, 'failed'::text, 'cancelled'::text])", name: "workout_bulk_operations_status"
  end

  create_table "workout_elevations", force: :cascade do |t|
    t.integer "algorithm_version", default: 1, null: false
    t.datetime "created_at", null: false
    t.string "dataset"
    t.datetime "generated_at"
    t.string "last_error"
    t.string "provider"
    t.integer "requests_count", default: 0, null: false
    t.jsonb "samples", default: [], null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "workout_id", null: false
    t.index ["workout_id"], name: "index_workout_elevations_on_workout_id", unique: true
    t.check_constraint "algorithm_version > 0", name: "workout_elevations_algorithm_version"
    t.check_constraint "jsonb_typeof(samples) = 'array'::text", name: "workout_elevations_samples"
    t.check_constraint "requests_count >= 0", name: "workout_elevations_requests_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'ready'::character varying::text, 'partial'::character varying::text, 'unavailable'::character varying::text, 'failed'::character varying::text])", name: "workout_elevations_status"
  end

  create_table "workout_equipments", id: false, force: :cascade do |t|
    t.bigint "equipment_id", null: false
    t.bigint "workout_id", null: false
    t.index ["equipment_id", "workout_id"], name: "index_workout_equipments_on_equipment_and_workout"
    t.index ["workout_id", "equipment_id"], name: "index_workout_equipments_on_workout_and_equipment", unique: true
  end

  create_table "workout_heart_rates", force: :cascade do |t|
    t.bigint "workout_id", null: false
    t.integer "version", null: false
    t.integer "histogram", null: false, array: true
    t.integer "sampled_seconds", null: false
    t.integer "recorded_seconds", null: false
    t.integer "zone_seconds", array: true
    t.decimal "load", precision: 8, scale: 1
    t.string "zones_fingerprint"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "covered_seconds", null: false
    t.integer "frozen_seconds", default: 0, null: false
    t.boolean "sparse", default: false, null: false
    t.index ["workout_id"], name: "index_workout_heart_rates_on_workout_id", unique: true
    t.check_constraint "(zone_seconds IS NULL) = (zones_fingerprint IS NULL) AND (load IS NULL OR zones_fingerprint IS NOT NULL)", name: "workout_heart_rates_zones"
    t.check_constraint "array_length(histogram, 1) = 191", name: "workout_heart_rates_histogram"
    t.check_constraint "load IS NULL OR load >= 0::numeric", name: "workout_heart_rates_load"
    t.check_constraint "sampled_seconds >= 0 AND recorded_seconds >= 0 AND covered_seconds >= 0 AND frozen_seconds >= 0", name: "workout_heart_rates_seconds"
    t.check_constraint "zone_seconds IS NULL OR array_length(zone_seconds, 1) = 5", name: "workout_heart_rates_zone_seconds"
  end

  create_table "workout_import_batch_equipments", id: false, force: :cascade do |t|
    t.bigint "workout_import_batch_id", null: false
    t.bigint "equipment_id", null: false
    t.index ["equipment_id", "workout_import_batch_id"], name: "index_import_batch_equipments_on_equipment_and_batch"
    t.index ["workout_import_batch_id", "equipment_id"], name: "index_import_batch_equipments_on_batch_and_equipment", unique: true
  end

  create_table "workout_import_batches", force: :cascade do |t|
    t.datetime "cancellation_requested_at"
    t.integer "cancelled_entries", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "discovered_at"
    t.integer "duplicate_entries", default: 0, null: false
    t.text "error_message"
    t.integer "failed_entries", default: 0, null: false
    t.bigint "import_connection_id"
    t.integer "imported_entries", default: 0, null: false
    t.text "notes"
    t.datetime "paused_until"
    t.integer "processed_entries", default: 0, null: false
    t.date "range_from"
    t.date "range_to"
    t.integer "skipped_entries", default: 0, null: false
    t.string "source", default: "file", null: false
    t.bigint "sport_id"
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.integer "total_entries", default: 0, null: false
    t.string "trigger", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.string "title"
    t.boolean "commute", default: false, null: false
    t.bigint "source_bytes", default: 0, null: false
    t.index ["import_connection_id"], name: "index_workout_import_batches_on_import_connection_id"
    t.index ["sport_id"], name: "index_workout_import_batches_on_sport_id"
    t.index ["user_id", "created_at"], name: "index_workout_import_batches_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_workout_import_batches_on_user_id"
    t.index ["uuid"], name: "index_workout_import_batches_on_uuid", unique: true
    t.check_constraint "cancelled_entries >= 0", name: "workout_import_batches_cancelled_entries"
    t.check_constraint "duplicate_entries >= 0", name: "workout_import_batches_duplicate_entries"
    t.check_constraint "failed_entries >= 0", name: "workout_import_batches_failed_entries"
    t.check_constraint "imported_entries >= 0", name: "workout_import_batches_imported_entries"
    t.check_constraint "processed_entries >= 0", name: "workout_import_batches_processed_entries"
    t.check_constraint "range_from IS NULL OR range_to IS NULL OR range_from <= range_to", name: "workout_import_batches_range"
    t.check_constraint "skipped_entries >= 0", name: "workout_import_batches_skipped_entries"
    t.check_constraint "source::text <> 'file'::text OR sport_id IS NOT NULL", name: "workout_import_batches_file_sport"
    t.check_constraint "source::text = ANY (ARRAY['file'::character varying::text, 'strava_archive'::character varying::text, 'garmin_connect'::character varying::text, 'exr'::character varying::text, 'withings'::character varying::text, 'zwift'::character varying::text])", name: "workout_import_batches_source"
    t.check_constraint "source_bytes >= 0", name: "workout_import_batches_source_bytes"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "workout_import_batches_status"
    t.check_constraint "total_entries >= 0", name: "workout_import_batches_total_entries"
    t.check_constraint "trigger::text = ANY (ARRAY['manual'::character varying::text, 'scheduled'::character varying::text, 'webhook'::character varying::text, 'api'::character varying::text])", name: "workout_import_batches_trigger"
  end

  create_table "workout_import_entries", force: :cascade do |t|
    t.bigint "batch_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "external_id"
    t.jsonb "metadata", default: {}, null: false
    t.integer "position", null: false
    t.string "skip_reason"
    t.string "source_digest", limit: 64
    t.string "source_key", null: false
    t.string "source_name", null: false
    t.string "source_path"
    t.string "sport_source", default: "unknown", null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.bigint "workout_id"
    t.index ["batch_id", "external_id"], name: "index_workout_import_entries_on_batch_id_and_external_id"
    t.index ["batch_id", "position"], name: "index_workout_import_entries_on_batch_id_and_position", unique: true
    t.index ["batch_id", "source_key"], name: "index_workout_import_entries_on_batch_id_and_source_key", unique: true
    t.index ["batch_id"], name: "index_workout_import_entries_on_batch_id"
    t.index ["source_digest"], name: "index_workout_import_entries_on_source_digest"
    t.index ["workout_id"], name: "index_workout_import_entries_on_workout_id"
    t.check_constraint "(status::text = 'skipped'::text) = (skip_reason IS NOT NULL)", name: "workout_import_entries_skipped_reason"
    t.check_constraint "\"position\" >= 0", name: "workout_import_entries_position"
    t.check_constraint "jsonb_typeof(metadata) = 'object'::text", name: "workout_import_entries_metadata_object"
    t.check_constraint "skip_reason IS NULL OR (skip_reason::text = ANY (ARRAY['no_geometry'::character varying::text, 'unsupported_sport'::character varying::text, 'no_file'::character varying::text]))", name: "workout_import_entries_skip_reason"
    t.check_constraint "sport_source::text = ANY (ARRAY['detected'::character varying::text, 'declared'::character varying::text, 'fallback'::character varying::text, 'unknown'::character varying::text, 'manual'::character varying::text])", name: "workout_import_entries_sport_source"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying::text, 'processing'::character varying::text, 'imported'::character varying::text, 'failed'::character varying::text, 'duplicate'::character varying::text, 'cancelled'::character varying::text, 'skipped'::character varying::text])", name: "workout_import_entries_status"
  end

  create_table "workout_participations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "declined_at"
    t.integer "detector_version"
    t.string "kind", default: "credit", null: false
    t.datetime "link_suggestion_dismissed_at"
    t.string "origin", default: "invitation", null: false
    t.datetime "owner_confirmed_at"
    t.bigint "participant_actor_id", null: false
    t.datetime "participant_confirmed_at"
    t.bigint "participant_workout_id"
    t.bigint "suggested_workout_id"
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.text "wire_activity_uri"
    t.datetime "withdrawn_at"
    t.bigint "workout_id", null: false
    t.bigint "workout_publication_id"
    t.index ["participant_actor_id"], name: "index_workout_participations_on_participant_actor_id"
    t.index ["participant_workout_id"], name: "index_workout_participations_live_recording", unique: true, where: "((withdrawn_at IS NULL) AND (participant_workout_id IS NOT NULL))"
    t.index ["suggested_workout_id"], name: "index_workout_participations_on_suggested_workout_id"
    t.index ["uuid"], name: "index_workout_participations_on_uuid", unique: true
    t.index ["workout_id", "participant_actor_id"], name: "index_workout_participations_live_pair", unique: true, where: "(withdrawn_at IS NULL)"
    t.index ["workout_id"], name: "index_workout_participations_on_workout_id"
    t.index ["workout_publication_id"], name: "index_workout_participations_on_workout_publication_id"
    t.check_constraint "(kind::text = 'link'::text) = (participant_workout_id IS NOT NULL)", name: "workout_participations_link_workout"
    t.check_constraint "kind::text = ANY (ARRAY['credit'::character varying::text, 'link'::character varying::text])", name: "workout_participations_kind"
    t.check_constraint "origin::text <> 'detection'::text OR kind::text = 'link'::text", name: "workout_participations_detection_is_link"
    t.check_constraint "origin::text = ANY (ARRAY['invitation'::character varying::text, 'detection'::character varying::text])", name: "workout_participations_origin"
    t.check_constraint "suggested_workout_id IS NULL OR kind::text = 'credit'::text", name: "workout_participations_suggestion_is_credit"
  end

  create_table "workout_photos", force: :cascade do |t|
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.bigint "workout_id", null: false
    t.bigint "user_id", null: false
    t.integer "position", null: false
    t.text "caption"
    t.string "status", default: "processing", null: false
    t.string "failure_reason"
    t.string "original_content_type", null: false
    t.integer "width"
    t.integer "height"
    t.datetime "taken_at_local"
    t.integer "taken_at_utc_offset"
    t.geography "exif_location", limit: {srid: 4326, type: "st_point", geographic: true}
    t.bigint "bytes_total", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.geography "location", limit: {srid: 4326, type: "st_point", geographic: true}
    t.string "location_source", default: "none", null: false
    t.float "track_distance"
    t.float "track_elapsed"
    t.index ["user_id"], name: "index_workout_photos_on_user_id"
    t.index ["uuid"], name: "index_workout_photos_on_uuid", unique: true
    t.check_constraint "(location IS NULL) = (location_source::text = ANY (ARRAY['none'::character varying::text, 'cleared'::character varying::text]))", name: "workout_photos_location_shape"
    t.check_constraint "\"position\" >= 0 AND bytes_total >= 0", name: "workout_photos_counters"
    t.check_constraint "caption IS NULL OR char_length(caption) <= 500", name: "workout_photos_caption_length"
    t.check_constraint "failure_reason IS NULL OR (failure_reason::text = ANY (ARRAY['unreadable'::character varying::text, 'too_large_dimensions'::character varying::text, 'processing_error'::character varying::text, 'quota_exceeded'::character varying::text]))", name: "workout_photos_failure_reason"
    t.check_constraint "location IS NULL AND track_distance IS NULL AND track_elapsed IS NULL OR location IS NOT NULL AND track_distance >= 0::double precision AND track_elapsed IS NOT NULL", name: "workout_photos_track_position"
    t.check_constraint "location_source::text = ANY (ARRAY['exif'::character varying::text, 'time'::character varying::text, 'manual'::character varying::text, 'none'::character varying::text, 'cleared'::character varying::text])", name: "workout_photos_location_source"
    t.check_constraint "original_content_type::text = ANY (ARRAY['image/jpeg'::character varying::text, 'image/png'::character varying::text, 'image/webp'::character varying::text, 'image/heic'::character varying::text])", name: "workout_photos_original_content_type"
    t.check_constraint "status::text = ANY (ARRAY['processing'::character varying::text, 'ready'::character varying::text, 'failed'::character varying::text])", name: "workout_photos_status"
    t.check_constraint "taken_at_utc_offset IS NULL OR taken_at_utc_offset >= '-50400'::integer AND taken_at_utc_offset <= 50400", name: "workout_photos_utc_offset"
    t.check_constraint "width IS NULL AND height IS NULL OR width IS NOT NULL AND height IS NOT NULL AND width > 0 AND height > 0", name: "workout_photos_dimensions"
    t.unique_constraint ["workout_id", "position"], deferrable: :deferred, name: "workout_photos_position_unique"
  end

  create_table "workout_place_names", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", default: "", null: false
    t.string "name", limit: 120, null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_id", null: false
    t.index ["user_id", "name"], name: "index_workout_place_names_on_user_and_name"
    t.index ["workout_id", "position"], name: "index_workout_place_names_on_workout_and_position", unique: true
    t.check_constraint "\"position\" >= 0", name: "workout_place_names_position"
  end

  create_table "workout_publication_photos", force: :cascade do |t|
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.bigint "workout_publication_id", null: false
    t.integer "position", null: false
    t.integer "width", null: false
    t.integer "height", null: false
    t.text "caption"
    t.float "distance"
    t.datetime "created_at", null: false
    t.index ["uuid"], name: "index_workout_publication_photos_on_uuid", unique: true
    t.index ["workout_publication_id", "position"], name: "index_workout_publication_photos_on_position", unique: true
    t.check_constraint "\"position\" >= 0 AND \"position\" < 20", name: "workout_publication_photos_position"
    t.check_constraint "caption IS NULL OR char_length(caption) <= 500", name: "workout_publication_photos_caption_length"
    t.check_constraint "distance IS NULL OR distance >= 0::double precision", name: "workout_publication_photos_distance"
    t.check_constraint "width > 0 AND height > 0", name: "workout_publication_photos_dimensions"
  end

  create_table "workout_publications", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.virtual "audience", type: :string, as: "(profile_snapshot ->> 'audience'::text)", stored: true
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "filtered_points_count", default: 0, null: false
    t.boolean "has_route", default: false, null: false
    t.datetime "location_data_purged_at"
    t.text "object_uri", null: false
    t.string "privacy_zone_fingerprint", null: false
    t.jsonb "profile_snapshot", default: {}, null: false
    t.datetime "published_at", null: false
    t.bigint "publishing_profile_id"
    t.jsonb "representation", default: {}, null: false
    t.jsonb "route_metadata", default: {}, null: false
    t.bigint "sanitized_gpx_blob_id"
    t.bigint "sanitized_route_image_blob_id"
    t.bigint "sanitized_route_image_dark_blob_id"
    t.datetime "scheduled_for"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.bigint "workout_id"
    t.index ["actor_id"], name: "index_workout_publications_on_actor_id"
    t.index ["object_uri"], name: "index_workout_publications_on_object_uri", unique: true
    t.index ["publishing_profile_id"], name: "index_workout_publications_on_publishing_profile_id"
    t.index ["sanitized_gpx_blob_id"], name: "index_workout_publications_on_sanitized_gpx_blob_id"
    t.index ["sanitized_route_image_blob_id"], name: "index_workout_publications_on_sanitized_route_image_blob_id"
    t.index ["sanitized_route_image_dark_blob_id"], name: "idx_on_sanitized_route_image_dark_blob_id_1f69aa945b"
    t.index ["scheduled_for"], name: "index_workout_publications_on_scheduled_for", where: "((status)::text = 'scheduled'::text)"
    t.index ["updated_at"], name: "index_workout_publications_on_cleanup", where: "(((status)::text = 'deleted'::text) AND (location_data_purged_at IS NULL))"
    t.index ["uuid"], name: "index_workout_publications_on_uuid", unique: true
    t.index ["workout_id", "audience"], name: "index_live_workout_publications_on_workout_and_audience", unique: true, where: "((status)::text = ANY (ARRAY[('active'::character varying)::text, ('scheduled'::character varying)::text]))"
    t.check_constraint "(status::text = ANY (ARRAY['active'::character varying::text, 'scheduled'::character varying::text])) AND deleted_at IS NULL OR status::text = 'deleted'::text AND deleted_at IS NOT NULL", name: "workout_publications_deletion_state"
    t.check_constraint "char_length(object_uri) > 0", name: "workout_publications_object_uri"
    t.check_constraint "filtered_points_count >= 0", name: "workout_publications_filtered_points_count"
    t.check_constraint "jsonb_typeof(profile_snapshot) = 'object'::text", name: "workout_publications_profile_snapshot_object"
    t.check_constraint "jsonb_typeof(representation) = 'object'::text", name: "workout_publications_representation_object"
    t.check_constraint "jsonb_typeof(route_metadata) = 'object'::text", name: "workout_publications_route_metadata_object"
    t.check_constraint "privacy_zone_fingerprint::text ~ '^[0-9a-f]{64}$'::text", name: "workout_publications_privacy_zone_fingerprint"
    t.check_constraint "status::text <> 'scheduled'::text OR scheduled_for IS NOT NULL", name: "workout_publications_scheduled_for"
    t.check_constraint "status::text = 'deleted'::text OR workout_id IS NOT NULL", name: "workout_publications_active_requires_source"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'scheduled'::character varying::text, 'deleted'::character varying::text])", name: "workout_publications_status"
  end

  create_table "workout_toponymies", force: :cascade do |t|
    t.integer "algorithm_version", default: 1, null: false
    t.datetime "created_at", null: false
    t.jsonb "finish_place", default: {}, null: false
    t.datetime "generated_at"
    t.string "last_error"
    t.jsonb "markers", default: [], null: false
    t.jsonb "places", default: [], null: false
    t.integer "places_algorithm_version", default: 0, null: false
    t.string "provider"
    t.integer "sampled_points_count", default: 0, null: false
    t.jsonb "samples", default: [], null: false
    t.jsonb "start_place", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "workout_id", null: false
    t.index ["workout_id"], name: "index_workout_toponymies_on_workout_id", unique: true
    t.check_constraint "algorithm_version > 0", name: "workout_toponymies_algorithm_version"
    t.check_constraint "jsonb_typeof(places) = 'array'::text", name: "workout_toponymies_places_array"
    t.check_constraint "jsonb_typeof(samples) = 'array'::text AND jsonb_typeof(markers) = 'array'::text", name: "workout_toponymies_arrays"
    t.check_constraint "jsonb_typeof(start_place) = 'object'::text AND jsonb_typeof(finish_place) = 'object'::text", name: "workout_toponymies_places"
    t.check_constraint "places_algorithm_version >= 0", name: "workout_toponymies_places_algorithm_version"
    t.check_constraint "sampled_points_count >= 0", name: "workout_toponymies_sampled_points_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'ready'::character varying::text, 'partial'::character varying::text, 'unavailable'::character varying::text, 'failed'::character varying::text])", name: "workout_toponymies_status"
  end

  create_table "workout_weathers", force: :cascade do |t|
    t.bigint "workout_id", null: false
    t.string "status", default: "pending", null: false
    t.integer "fetch_version", default: 0, null: false
    t.integer "analysis_version", default: 0, null: false
    t.string "endpoint"
    t.jsonb "samples", default: [], null: false
    t.jsonb "responses", default: [], null: false
    t.jsonb "series", default: [], null: false
    t.jsonb "exposure", default: {}, null: false
    t.jsonb "summary", default: {}, null: false
    t.integer "requests_count", default: 0, null: false
    t.datetime "fetched_at"
    t.string "unavailable_reason"
    t.string "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fetched_at"], name: "index_workout_weathers_on_fetched_at"
    t.index ["workout_id"], name: "index_workout_weathers_on_workout_id", unique: true
    t.check_constraint "endpoint IS NULL OR (endpoint::text = ANY (ARRAY['forecast'::character varying::text, 'archive'::character varying::text]))", name: "workout_weathers_endpoint"
    t.check_constraint "fetch_version >= 0 AND analysis_version >= 0 AND requests_count >= 0", name: "workout_weathers_counters"
    t.check_constraint "jsonb_typeof(exposure) = 'object'::text AND jsonb_typeof(summary) = 'object'::text", name: "workout_weathers_objects"
    t.check_constraint "jsonb_typeof(samples) = 'array'::text AND jsonb_typeof(responses) = 'array'::text AND jsonb_typeof(series) = 'array'::text", name: "workout_weathers_arrays"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'ready'::character varying::text, 'unavailable'::character varying::text, 'failed'::character varying::text])", name: "workout_weathers_status"
  end

  create_table "workouts", force: :cascade do |t|
    t.integer "analysis_version", default: 1, null: false
    t.decimal "ascent", precision: 12, scale: 2, null: false
    t.integer "average_cadence"
    t.integer "average_heart_rate"
    t.integer "average_pace"
    t.integer "average_power"
    t.decimal "average_speed", precision: 10, scale: 4, null: false
    t.integer "best_pace"
    t.float "bounds", array: true
    t.integer "calories"
    t.datetime "comments_closed_at"
    t.boolean "commute", default: false, null: false
    t.string "contested_metrics", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.datetime "credit_detached_at"
    t.bigint "credited_by_actor_id"
    t.bigint "credited_from_workout_id"
    t.decimal "credited_max_climb", precision: 12, scale: 2
    t.jsonb "data_anomalies", default: {}, null: false
    t.decimal "descent", precision: 12, scale: 2, null: false
    t.text "description"
    t.decimal "distance", precision: 14, scale: 3, null: false
    t.integer "duration", null: false
    t.string "elevation_filter"
    t.string "elevation_source", default: "device", null: false
    t.string "elevation_source_requested"
    t.string "external_id"
    t.integer "grade_adjusted_pace"
    t.bigint "import_connection_id"
    t.integer "import_detection_version", default: 0, null: false
    t.string "import_format"
    t.integer "loop_reuse_version", default: 0, null: false
    t.integer "max_cadence"
    t.decimal "max_elevation", precision: 10, scale: 2
    t.integer "max_heart_rate"
    t.integer "max_power"
    t.decimal "max_speed", precision: 10, scale: 4
    t.decimal "min_elevation", precision: 10, scale: 2
    t.integer "moving_time", null: false
    t.text "notes"
    t.string "origin", default: "import", null: false
    t.integer "pause_time", null: false
    t.jsonb "places", default: [], null: false
    t.integer "points_count"
    t.boolean "recorded_elevation", default: false, null: false
    t.bigint "remote_participation_id"
    t.integer "route_image_version", default: 0, null: false
    t.string "source"
    t.string "source_digest", limit: 64
    t.bigint "sport_id", null: false
    t.geography "start_point", limit: {srid: 4326, type: "st_point", geographic: true}
    t.datetime "started_at", null: false
    t.string "title"
    t.integer "together_detection_version", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.jsonb "weather_end"
    t.jsonb "weather_start"
    t.integer "heart_rate_version", default: 0, null: false
    t.integer "photo_time_offset_seconds", default: 0, null: false
    t.bigint "time_shift_seconds", default: 0, null: false
    t.boolean "photos_ordered_by_owner", default: false, null: false
    t.integer "route_suggestion_version", default: 0, null: false
    t.index ["analysis_version", "id"], name: "index_workouts_on_analysis_version_and_id"
    t.index ["credited_by_actor_id"], name: "index_workouts_on_credited_by_actor_id"
    t.index ["credited_from_workout_id", "user_id"], name: "index_workouts_on_live_credit", unique: true, where: "(credited_from_workout_id IS NOT NULL)"
    t.index ["import_connection_id", "external_id"], name: "index_workouts_on_import_connection_external_id", unique: true, where: "((import_connection_id IS NOT NULL) AND (external_id IS NOT NULL))"
    t.index ["import_detection_version", "id"], name: "index_workouts_on_import_detection_version_and_id"
    t.index ["loop_reuse_version", "id"], name: "index_workouts_on_loop_reuse_version_and_id"
    t.index ["remote_participation_id"], name: "index_workouts_on_remote_participation", unique: true, where: "(remote_participation_id IS NOT NULL)"
    t.index ["route_image_version", "id"], name: "index_workouts_on_route_image_version_and_id"
    t.index ["route_suggestion_version", "id"], name: "index_workouts_on_route_suggestion_version_and_id", where: "((origin)::text = 'import'::text)"
    t.index ["sport_id"], name: "index_workouts_on_sport_id"
    t.index ["start_point"], name: "index_workouts_on_start_point", using: :gist
    t.index ["started_at"], name: "index_workouts_on_recording_started_at", where: "((origin)::text = 'import'::text)"
    t.index ["together_detection_version", "id"], name: "index_workouts_on_together_detection_version_and_id", where: "((origin)::text = 'import'::text)"
    t.index ["user_id", "credited_by_actor_id", "started_at"], name: "index_workouts_on_credit_reattachment", where: "((origin)::text = 'credit'::text)"
    t.index ["user_id", "source_digest"], name: "index_workouts_on_user_and_source_digest", unique: true, where: "(source_digest IS NOT NULL)"
    t.index ["user_id", "sport_id", "ascent"], name: "index_workouts_on_user_sport_ascent"
    t.index ["user_id", "sport_id", "average_pace"], name: "index_workouts_on_user_sport_average_pace", where: "(average_pace IS NOT NULL)"
    t.index ["user_id", "sport_id", "average_speed"], name: "index_workouts_on_user_sport_average_speed"
    t.index ["user_id", "sport_id", "best_pace"], name: "index_workouts_on_user_sport_best_pace", where: "(best_pace IS NOT NULL)"
    t.index ["user_id", "sport_id", "distance"], name: "index_workouts_on_user_sport_distance"
    t.index ["user_id", "sport_id", "max_speed"], name: "index_workouts_on_user_sport_max_speed", where: "(max_speed IS NOT NULL)"
    t.index ["user_id", "sport_id", "moving_time"], name: "index_workouts_on_user_sport_moving_time"
    t.index ["user_id", "started_at"], name: "index_workouts_on_user_id_and_started_at", order: { started_at: :desc }
    t.index ["uuid"], name: "index_workouts_on_uuid", unique: true
    t.check_constraint "(average_heart_rate IS NULL OR average_heart_rate >= 0) AND (max_heart_rate IS NULL OR max_heart_rate >= 0) AND (average_cadence IS NULL OR average_cadence >= 0) AND (max_cadence IS NULL OR max_cadence >= 0) AND (average_power IS NULL OR average_power >= 0) AND (max_power IS NULL OR max_power >= 0)", name: "workouts_physiological_metrics"
    t.check_constraint "(origin::text = ANY (ARRAY['import'::character varying::text, 'manual'::character varying::text])) AND credited_from_workout_id IS NULL AND credited_by_actor_id IS NULL AND credit_detached_at IS NULL AND credited_max_climb IS NULL OR origin::text = 'credit'::text AND credited_by_actor_id IS NOT NULL AND (credited_from_workout_id IS NULL OR credit_detached_at IS NULL) AND source_digest IS NULL AND import_connection_id IS NULL AND external_id IS NULL AND source IS NULL AND description IS NULL AND notes IS NULL AND calories IS NULL AND average_heart_rate IS NULL AND max_heart_rate IS NULL AND average_cadence IS NULL AND max_cadence IS NULL AND average_power IS NULL AND max_power IS NULL AND grade_adjusted_pace IS NULL AND min_elevation IS NULL AND max_elevation IS NULL AND weather_start IS NULL AND weather_end IS NULL AND commute = false AND places = '[]'::jsonb AND data_anomalies = '{}'::jsonb", name: "workouts_credit_shape"
    t.check_constraint "analysis_version > 0", name: "workouts_analysis_version"
    t.check_constraint "average_pace IS NULL OR average_pace >= 0", name: "workouts_average_pace"
    t.check_constraint "best_pace IS NULL OR best_pace >= 0", name: "workouts_best_pace"
    t.check_constraint "calories IS NULL OR calories >= 0", name: "workouts_calories"
    t.check_constraint "cardinality(bounds) = 4", name: "workouts_bounds"
    t.check_constraint "char_length(description) <= 10000", name: "workouts_description_length"
    t.check_constraint "char_length(notes) <= 500", name: "workouts_notes_length"
    t.check_constraint "char_length(title::text) <= 255", name: "workouts_title_length"
    t.check_constraint "distance >= 0::numeric AND ascent >= 0::numeric AND descent >= 0::numeric AND average_speed >= 0::numeric", name: "workouts_non_negative_metrics"
    t.check_constraint "duration >= 0", name: "workouts_duration"
    t.check_constraint "elevation_filter IS NULL OR (elevation_filter::text = ANY (ARRAY['barometric'::character varying::text, 'gps'::character varying::text, 'dem'::character varying::text]))", name: "workouts_elevation_filter"
    t.check_constraint "elevation_source::text = ANY (ARRAY['device'::character varying::text, 'dem'::character varying::text])", name: "workouts_elevation_source"
    t.check_constraint "elevation_source_requested IS NULL OR (elevation_source_requested::text = ANY (ARRAY['device'::character varying::text, 'dem'::character varying::text]))", name: "workouts_elevation_source_requested"
    t.check_constraint "grade_adjusted_pace IS NULL OR grade_adjusted_pace >= 0", name: "workouts_grade_adjusted_pace"
    t.check_constraint "import_detection_version >= 0", name: "workouts_import_detection_version"
    t.check_constraint "import_format::text = ANY (ARRAY['gpx'::character varying::text, 'fit'::character varying::text, 'tcx'::character varying::text, 'kml'::character varying::text])", name: "workouts_import_format"
    t.check_constraint "jsonb_typeof(places) = 'array'::text", name: "workouts_places_array"
    t.check_constraint "loop_reuse_version >= 0", name: "workouts_loop_reuse_version"
    t.check_constraint "max_speed IS NULL OR max_speed >= 0::numeric", name: "workouts_max_speed"
    t.check_constraint "moving_time >= 0 AND moving_time <= duration", name: "workouts_moving_time"
    t.check_constraint "origin::text <> 'manual'::text OR source_digest IS NULL AND import_connection_id IS NULL AND external_id IS NULL AND source IS NULL AND average_cadence IS NULL AND max_cadence IS NULL AND max_power IS NULL AND max_speed IS NULL AND best_pace IS NULL AND grade_adjusted_pace IS NULL AND min_elevation IS NULL AND max_elevation IS NULL AND elevation_filter IS NULL AND elevation_source::text = 'device'::text AND elevation_source_requested IS NULL AND recorded_elevation = false AND weather_start IS NULL AND weather_end IS NULL AND places = '[]'::jsonb AND data_anomalies = '{}'::jsonb AND contested_metrics = '{}'::character varying[]", name: "workouts_manual_shape"
    t.check_constraint "origin::text = 'import'::text AND points_count IS NOT NULL AND import_format IS NOT NULL AND (start_point IS NULL AND bounds IS NULL OR start_point IS NOT NULL AND bounds IS NOT NULL) OR (origin::text = ANY (ARRAY['credit'::character varying::text, 'manual'::character varying::text])) AND start_point IS NULL AND bounds IS NULL AND points_count IS NULL AND import_format IS NULL", name: "workouts_recording_shape"
    t.check_constraint "origin::text = ANY (ARRAY['import'::character varying::text, 'credit'::character varying::text, 'manual'::character varying::text])", name: "workouts_origin"
    t.check_constraint "pause_time = (duration - moving_time)", name: "workouts_pause_time"
    t.check_constraint "photo_time_offset_seconds >= '-50400'::integer AND photo_time_offset_seconds <= 50400", name: "workouts_photo_time_offset"
    t.check_constraint "points_count >= 2", name: "workouts_points_count"
    t.check_constraint "remote_participation_id IS NULL OR origin::text = 'credit'::text AND credited_from_workout_id IS NULL", name: "workouts_remote_credit_shape"
    t.check_constraint "route_image_version >= 0", name: "workouts_route_image_version"
    t.check_constraint "route_suggestion_version >= 0", name: "workouts_route_suggestion_version"
    t.check_constraint "together_detection_version >= 0", name: "workouts_together_detection_version"
  end

  add_foreign_key "account_exports", "users", on_delete: :cascade
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "actors", "users", on_delete: :nullify
  add_foreign_key "admin_events", "users", on_delete: :nullify
  add_foreign_key "api_idempotency_keys", "api_tokens", on_delete: :cascade
  add_foreign_key "api_tokens", "users", on_delete: :cascade
  add_foreign_key "best_efforts", "sports"
  add_foreign_key "best_efforts", "users", on_delete: :cascade
  add_foreign_key "best_efforts", "workouts", on_delete: :cascade
  add_foreign_key "comments", "actors", column: "relayed_by_actor_id", on_delete: :restrict
  add_foreign_key "comments", "actors", on_delete: :restrict
  add_foreign_key "comments", "comments", column: "parent_id", on_delete: :nullify
  add_foreign_key "comments", "remote_notes", on_delete: :cascade
  add_foreign_key "comments", "workouts", on_delete: :cascade
  add_foreign_key "detected_laps", "segment_efforts", on_delete: :nullify
  add_foreign_key "detected_laps", "workouts", on_delete: :cascade
  add_foreign_key "effort_records", "sports"
  add_foreign_key "effort_records", "users", on_delete: :cascade
  add_foreign_key "effort_records", "workouts", on_delete: :nullify
  add_foreign_key "equipments", "equipment_types"
  add_foreign_key "equipments", "import_connections", on_delete: :nullify
  add_foreign_key "equipments", "users", on_delete: :cascade
  add_foreign_key "federation_actor_blocks", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "federation_deliveries", "federation_outbox_events", column: "outbox_event_id", on_delete: :restrict
  add_foreign_key "federation_delivery_recipients", "federation_deliveries", column: "delivery_id", on_delete: :cascade
  add_foreign_key "federation_domain_blocks", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "federation_inbox_items", "actors", column: "recipient_actor_id", on_delete: :restrict
  add_foreign_key "federation_outbox_events", "actors", on_delete: :restrict
  add_foreign_key "federation_outbox_events", "segment_publications"
  add_foreign_key "federation_outbox_events", "workout_publications"
  add_foreign_key "federation_peer_policies", "users", column: "approved_by_id", on_delete: :nullify
  add_foreign_key "followings", "actors", column: "followed_actor_id", on_delete: :restrict
  add_foreign_key "followings", "actors", column: "follower_actor_id", on_delete: :restrict
  add_foreign_key "funding_contributions", "funding_subscriptions"
  add_foreign_key "funding_contributions", "users", on_delete: :cascade
  add_foreign_key "funding_reversals", "funding_contributions", on_delete: :cascade
  add_foreign_key "funding_subscriptions", "users", on_delete: :cascade
  add_foreign_key "identities", "users"
  add_foreign_key "import_connections", "sports", column: "fallback_sport_id", on_delete: :nullify
  add_foreign_key "import_connections", "users", on_delete: :cascade
  add_foreign_key "laps", "workouts", on_delete: :cascade
  add_foreign_key "notifications", "actors", on_delete: :nullify
  add_foreign_key "notifications", "users", on_delete: :cascade
  add_foreign_key "people_suggestion_dismissals", "actors", on_delete: :cascade
  add_foreign_key "people_suggestion_dismissals", "users", on_delete: :cascade
  add_foreign_key "privacy_zones", "users"
  add_foreign_key "publishing_profiles", "users"
  add_foreign_key "push_subscriptions", "sessions", on_delete: :cascade
  add_foreign_key "push_subscriptions", "users", on_delete: :cascade
  add_foreign_key "reactions", "actors", on_delete: :restrict
  add_foreign_key "reactions", "remote_notes", on_delete: :cascade
  add_foreign_key "reactions", "workouts", on_delete: :cascade
  add_foreign_key "records", "sports"
  add_foreign_key "records", "users", on_delete: :cascade
  add_foreign_key "records", "workouts", on_delete: :nullify
  add_foreign_key "recovery_codes", "users"
  add_foreign_key "remote_note_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "remote_note_attachments", "remote_notes", on_delete: :cascade
  add_foreign_key "remote_note_recipients", "actors", column: "recipient_actor_id"
  add_foreign_key "remote_note_recipients", "federation_inbox_items", column: "inbox_item_id", on_delete: :nullify
  add_foreign_key "remote_note_recipients", "remote_notes", on_delete: :cascade
  add_foreign_key "remote_notes", "actors"
  add_foreign_key "remote_participations", "actors", column: "recipient_actor_id", on_delete: :restrict
  add_foreign_key "remote_participations", "remote_notes", on_delete: :cascade
  add_foreign_key "remote_segment_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "remote_segment_attachments", "remote_segments", on_delete: :cascade
  add_foreign_key "remote_segment_recipients", "actors", column: "recipient_actor_id"
  add_foreign_key "remote_segment_recipients", "federation_inbox_items", column: "inbox_item_id", on_delete: :nullify
  add_foreign_key "remote_segment_recipients", "remote_segments", on_delete: :cascade
  add_foreign_key "remote_segments", "actors"
  add_foreign_key "route_suggestion_workouts", "route_suggestions", on_delete: :cascade
  add_foreign_key "route_suggestion_workouts", "workouts", on_delete: :cascade
  add_foreign_key "route_suggestions", "segments", on_delete: :nullify
  add_foreign_key "route_suggestions", "sports", on_delete: :cascade
  add_foreign_key "route_suggestions", "users", on_delete: :cascade
  add_foreign_key "route_suggestions", "workouts", column: "reference_workout_id", on_delete: :nullify
  add_foreign_key "segment_efforts", "segments", on_delete: :cascade
  add_foreign_key "segment_efforts", "sports"
  add_foreign_key "segment_efforts", "users"
  add_foreign_key "segment_efforts", "workouts", on_delete: :cascade
  add_foreign_key "segment_opt_outs", "segments", on_delete: :cascade
  add_foreign_key "segment_opt_outs", "users", on_delete: :cascade
  add_foreign_key "segment_publications", "active_storage_blobs", column: "sanitized_gpx_blob_id"
  add_foreign_key "segment_publications", "active_storage_blobs", column: "sanitized_route_image_blob_id"
  add_foreign_key "segment_publications", "active_storage_blobs", column: "sanitized_route_image_dark_blob_id"
  add_foreign_key "segment_publications", "actors"
  add_foreign_key "segment_publications", "segments", on_delete: :nullify
  add_foreign_key "segments", "remote_segments", on_delete: :nullify
  add_foreign_key "segments", "sports"
  add_foreign_key "segments", "users"
  add_foreign_key "segments", "workouts", column: "source_workout_id", on_delete: :nullify
  add_foreign_key "sessions", "users"
  add_foreign_key "track_segments", "workouts"
  add_foreign_key "users", "sports", column: "default_cycling_sport_id", on_delete: :nullify
  add_foreign_key "users", "sports", column: "default_running_sport_id", on_delete: :nullify
  add_foreign_key "users", "sports", column: "default_walking_sport_id", on_delete: :nullify
  add_foreign_key "webauthn_credentials", "users"
  add_foreign_key "webhook_deliveries", "webhook_deliveries", column: "redelivery_of_id", on_delete: :nullify
  add_foreign_key "webhook_deliveries", "webhook_endpoints", on_delete: :cascade
  add_foreign_key "webhook_deliveries", "webhook_events", on_delete: :cascade
  add_foreign_key "webhook_endpoints", "users", on_delete: :cascade
  add_foreign_key "webhook_events", "users", on_delete: :cascade
  add_foreign_key "workout_auto_publications", "publishing_profiles", on_delete: :nullify
  add_foreign_key "workout_auto_publications", "workout_publications", on_delete: :nullify
  add_foreign_key "workout_auto_publications", "workouts", on_delete: :cascade
  add_foreign_key "workout_bulk_operation_items", "workout_bulk_operations", on_delete: :cascade
  add_foreign_key "workout_bulk_operation_items", "workouts", on_delete: :nullify
  add_foreign_key "workout_bulk_operations", "users", on_delete: :cascade
  add_foreign_key "workout_elevations", "workouts", on_delete: :cascade
  add_foreign_key "workout_equipments", "equipments", on_delete: :cascade
  add_foreign_key "workout_equipments", "workouts", on_delete: :cascade
  add_foreign_key "workout_heart_rates", "workouts", on_delete: :cascade
  add_foreign_key "workout_import_batch_equipments", "equipments", on_delete: :cascade
  add_foreign_key "workout_import_batch_equipments", "workout_import_batches", on_delete: :cascade
  add_foreign_key "workout_import_batches", "import_connections", on_delete: :nullify
  add_foreign_key "workout_import_batches", "sports"
  add_foreign_key "workout_import_batches", "users"
  add_foreign_key "workout_import_entries", "workout_import_batches", column: "batch_id"
  add_foreign_key "workout_import_entries", "workouts", on_delete: :nullify
  add_foreign_key "workout_participations", "actors", column: "participant_actor_id", on_delete: :restrict
  add_foreign_key "workout_participations", "workout_publications", on_delete: :nullify
  add_foreign_key "workout_participations", "workouts", column: "participant_workout_id", on_delete: :cascade
  add_foreign_key "workout_participations", "workouts", column: "suggested_workout_id", on_delete: :nullify
  add_foreign_key "workout_participations", "workouts", on_delete: :cascade
  add_foreign_key "workout_photos", "users", on_delete: :cascade
  add_foreign_key "workout_photos", "workouts", on_delete: :cascade
  add_foreign_key "workout_place_names", "users", on_delete: :cascade
  add_foreign_key "workout_place_names", "workouts", on_delete: :cascade
  add_foreign_key "workout_publication_photos", "workout_publications", on_delete: :cascade
  add_foreign_key "workout_publications", "active_storage_blobs", column: "sanitized_gpx_blob_id"
  add_foreign_key "workout_publications", "active_storage_blobs", column: "sanitized_route_image_blob_id"
  add_foreign_key "workout_publications", "active_storage_blobs", column: "sanitized_route_image_dark_blob_id"
  add_foreign_key "workout_publications", "actors"
  add_foreign_key "workout_publications", "publishing_profiles", on_delete: :nullify
  add_foreign_key "workout_publications", "workouts", on_delete: :nullify
  add_foreign_key "workout_toponymies", "workouts", on_delete: :cascade
  add_foreign_key "workout_weathers", "workouts", on_delete: :cascade
  add_foreign_key "workouts", "actors", column: "credited_by_actor_id"
  add_foreign_key "workouts", "import_connections", on_delete: :nullify
  add_foreign_key "workouts", "remote_participations", on_delete: :nullify
  add_foreign_key "workouts", "sports"
  add_foreign_key "workouts", "users"
  add_foreign_key "workouts", "workouts", column: "credited_from_workout_id", on_delete: :nullify
end
