# frozen_string_literal: true

# docs/dev/AI.md §9: the operator's summary sweep is audited like every other
# backfill. The action list mirrors admin_events_action, plus this one.
class AddSummariesBackfillAction < ActiveRecord::Migration[8.1]
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
    route_suggestions_backfill_enqueued
  ].freeze
  ADDED_ACTION = "summaries_backfill_enqueued"

  def up = replace_actions(PREVIOUS_ACTIONS + [ ADDED_ACTION ])
  def down = replace_actions(PREVIOUS_ACTIONS)

  private

  def replace_actions(values)
    remove_check_constraint :admin_events, name: "admin_events_action"
    add_check_constraint :admin_events, "action IN (#{values.map { "'#{it}'" }.join(', ')})",
                         name: "admin_events_action"
  end
end
