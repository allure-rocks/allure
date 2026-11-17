# frozen_string_literal: true

# docs/dev/ACCOUNT.md: the deletion lifecycle is audited, and a ready export is
# notified in-app.
class AddAccountLifecycleKinds < ActiveRecord::Migration[8.1]
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
  ].freeze
  ADDED_ACTIONS = %w[account_deletion_scheduled account_deletion_cancelled account_deleted].freeze

  PREVIOUS_KINDS = %w[
    follow_request follow_accepted publication_activated reaction
    participation_requested participation_suggested participation_confirmed
    participation_source_deleted comment import_connection_expired import_connection_revoked
    auto_published auto_publication_failed webhook_disabled participation_link_suggested
  ].freeze
  ADDED_KIND = "account_export_ready"

  def up
    replace(:admin_events, "action", "admin_events_action", PREVIOUS_ACTIONS + ADDED_ACTIONS)
    replace(:notifications, "kind", "notifications_kind", PREVIOUS_KINDS + [ ADDED_KIND ])
  end

  def down
    replace(:notifications, "kind", "notifications_kind", PREVIOUS_KINDS)
    replace(:admin_events, "action", "admin_events_action", PREVIOUS_ACTIONS)
  end

  private

  def replace(table, column, name, values)
    remove_check_constraint table, name: name
    add_check_constraint table, "#{column} IN (#{values.map { "'#{it}'" }.join(', ')})", name: name
  end
end
