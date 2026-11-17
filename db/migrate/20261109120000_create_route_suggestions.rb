# frozen_string_literal: true

# docs/dev/SEGMENTS.md: a recurring route is suggested, never created. The
# suggestion is owner-only bookkeeping — one row per circuit, one membership
# row per recording, and a generation marker on the recordings the detector
# has already examined. Nothing here is a course and nothing is published.
class CreateRouteSuggestions < ActiveRecord::Migration[8.1]
  PREVIOUS_ACTIONS = %w[
    domain_blocked domain_unblocked actor_blocked actor_unblocked
    peer_policy_set peer_policy_removed media_retried
    job_retried job_discarded jobs_retried jobs_discarded
    queue_paused queue_resumed analysis_backfill_enqueued
    elevation_backfill_enqueued places_backfill_enqueued toponymy_backfill_enqueued
    import_redetection_enqueued workouts_rebuild_enqueued route_images_backfill_enqueued
    segment_route_images_backfill_enqueued loop_reuse_backfill_enqueued
    elevation_profiles_backfill_enqueued
    publication_withdrawn publication_schedule_cancelled
    account_suspended account_reinstated
    invitation_created invitation_revoked
    second_factor_reset password_setup_sent
    import_connection_revoked
    api_token_revoked webhook_endpoint_disabled
    segment_places_backfill_enqueued
    together_detection_backfill_enqueued
    account_deletion_scheduled account_deletion_cancelled account_deleted
    weather_backfill_enqueued
    segment_terrain_elevation_backfill_enqueued
    heart_rate_backfill_enqueued
    photo_quota_changed
    funding_granted funding_revoked funding_attached
  ].freeze
  ADDED_ACTION = "route_suggestions_backfill_enqueued"

  def up
    create_table :route_suggestions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :sport, null: false, foreign_key: { on_delete: :cascade }
      t.references :reference_workout, foreign_key: { to_table: :workouts, on_delete: :nullify }
      t.references :segment, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: "pending"
      t.timestamps

      t.index %i[user_id status]
    end
    add_check_constraint :route_suggestions,
                         "status IN ('pending', 'dismissed', 'accepted')",
                         name: "route_suggestions_status"

    create_table :route_suggestion_workouts do |t|
      t.references :route_suggestion, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.timestamps

      # A recording belongs to one suggestion only: the detector's verdict is
      # final until the owner acts on it.
      t.index :workout_id, unique: true
      t.index %i[route_suggestion_id workout_id], unique: true
    end

    add_column :workouts, :route_suggestion_version, :integer, default: 0, null: false
    add_check_constraint :workouts, "route_suggestion_version >= 0", name: "workouts_route_suggestion_version"
    add_index :workouts, %i[route_suggestion_version id], where: "origin = 'import'",
                                                          name: "index_workouts_on_route_suggestion_version_and_id"

    replace_actions(PREVIOUS_ACTIONS + [ ADDED_ACTION ])
  end

  def down
    replace_actions(PREVIOUS_ACTIONS)
    remove_index :workouts, name: "index_workouts_on_route_suggestion_version_and_id"
    remove_check_constraint :workouts, name: "workouts_route_suggestion_version"
    remove_column :workouts, :route_suggestion_version
    drop_table :route_suggestion_workouts
    drop_table :route_suggestions
  end

  private

  def replace_actions(values)
    remove_check_constraint :admin_events, name: "admin_events_action"
    add_check_constraint :admin_events, "action IN (#{values.map { "'#{it}'" }.join(', ')})", name: "admin_events_action"
  end
end
