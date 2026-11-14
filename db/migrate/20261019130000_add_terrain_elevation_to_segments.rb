# frozen_string_literal: true

# PLAN_ELEVATION.md §10: a course carries the source of its frozen elevation
# figures (the recording device's or the terrain service's) and the state of
# its terrain request; the operator backfills it from /admin/jobs.
class AddTerrainElevationToSegments < ActiveRecord::Migration[8.1]
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
  ].freeze
  ADDED_ACTION = "segment_terrain_elevation_backfill_enqueued"

  def up
    add_column :segments, :elevation_source, :string, null: false, default: "device"
    add_column :segments, :elevation_status, :string
    add_check_constraint :segments, "elevation_source IN ('device', 'dem')", name: "segments_elevation_source"
    add_check_constraint :segments,
                         "elevation_status IS NULL OR elevation_status IN ('ready', 'unavailable', 'failed')",
                         name: "segments_elevation_status"

    replace_actions(PREVIOUS_ACTIONS + [ ADDED_ACTION ])
  end

  def down
    replace_actions(PREVIOUS_ACTIONS)
    remove_check_constraint :segments, name: "segments_elevation_status"
    remove_check_constraint :segments, name: "segments_elevation_source"
    remove_column :segments, :elevation_status
    remove_column :segments, :elevation_source
  end

  private

  def replace_actions(values)
    remove_check_constraint :admin_events, name: "admin_events_action"
    add_check_constraint :admin_events, "action IN (#{values.map { "'#{it}'" }.join(', ')})", name: "admin_events_action"
  end
end
