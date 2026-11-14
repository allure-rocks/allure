# frozen_string_literal: true

class AddFundingEventKinds < ActiveRecord::Migration[8.1]
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
    account_suspended account_reinstated invitation_created invitation_revoked
    second_factor_reset password_setup_sent import_connection_revoked
    api_token_revoked webhook_endpoint_disabled segment_places_backfill_enqueued
    together_detection_backfill_enqueued
    account_deletion_scheduled account_deletion_cancelled account_deleted
    weather_backfill_enqueued segment_terrain_elevation_backfill_enqueued
    heart_rate_backfill_enqueued photo_quota_changed
  ].freeze
  PREVIOUS_KINDS = %w[
    follow_request follow_accepted publication_activated reaction
    participation_requested participation_suggested participation_confirmed
    participation_source_deleted comment import_connection_expired import_connection_revoked
    auto_published auto_publication_failed webhook_disabled participation_link_suggested
    account_export_ready
  ].freeze

  def up
    replace(:admin_events, "action", PREVIOUS_ACTIONS + %w[funding_granted funding_revoked])
    replace(:notifications, "kind", PREVIOUS_KINDS + %w[funding_recorded])
  end

  def down
    replace(:notifications, "kind", PREVIOUS_KINDS)
    replace(:admin_events, "action", PREVIOUS_ACTIONS)
  end

  private

  def replace(table, column, values)
    name = "#{table}_#{column}"
    remove_check_constraint table, name: name
    add_check_constraint table, "#{column} IN (#{values.map { "'#{it}'" }.join(', ')})", name: name
  end
end
