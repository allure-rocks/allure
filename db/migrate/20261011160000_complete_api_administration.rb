# frozen_string_literal: true

# PLAN_API.md §11.4, §14 (Slice 6): the `webhook_disabled` notification and
# its switch, the operator's audited token revocation and webhook disabling,
# and a public id for participations, which webhook payloads name.
class CompleteApiAdministration < ActiveRecord::Migration[8.1]
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
  ].freeze
  ADDED_ACTIONS = %w[api_token_revoked webhook_endpoint_disabled].freeze

  PREVIOUS_KINDS = %w[
    follow_request follow_accepted publication_activated reaction
    participation_requested participation_suggested participation_confirmed
    comment import_connection_expired import_connection_revoked
    auto_published auto_publication_failed
  ].freeze
  ADDED_KIND = "webhook_disabled"

  def up
    add_column :users, :notify_webhooks, :boolean, null: false, default: true
    add_column :workout_participations, :uuid, :uuid, null: false, default: -> { "gen_random_uuid()" }
    add_index :workout_participations, :uuid, unique: true
    replace_constraint(:admin_events, "admin_events_action", :action, PREVIOUS_ACTIONS + ADDED_ACTIONS)
    replace_constraint(:notifications, "notifications_kind", :kind, PREVIOUS_KINDS + [ ADDED_KIND ])
  end

  def down
    replace_constraint(:notifications, "notifications_kind", :kind, PREVIOUS_KINDS)
    replace_constraint(:admin_events, "admin_events_action", :action, PREVIOUS_ACTIONS)
    remove_index :workout_participations, :uuid
    remove_column :workout_participations, :uuid
    remove_column :users, :notify_webhooks
  end

  private

  def replace_constraint(table, name, column, values)
    remove_check_constraint table, name: name
    add_check_constraint table, "#{column} IN (#{values.map { "'#{it}'" }.join(', ')})", name:
  end
end
