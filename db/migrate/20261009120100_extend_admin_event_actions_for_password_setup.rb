# frozen_string_literal: true

# docs/dev/AUTH.md: the operator emails a password-less account a one-time
# password-setting link, and the audit log records it. AdminEvent::ACTIONS is
# mirrored by a checked constraint; historical actions stay allowed.
class ExtendAdminEventActionsForPasswordSetup < ActiveRecord::Migration[8.1]
  ACTIONS = %w[
    domain_blocked domain_unblocked actor_blocked actor_unblocked
    peer_policy_set peer_policy_removed media_retried
    job_retried job_discarded jobs_retried jobs_discarded
    queue_paused queue_resumed analysis_backfill_enqueued
    elevation_backfill_enqueued places_backfill_enqueued
    import_redetection_enqueued workouts_rebuild_enqueued route_images_backfill_enqueued
    segment_route_images_backfill_enqueued loop_reuse_backfill_enqueued
    elevation_profiles_backfill_enqueued
    publication_withdrawn publication_schedule_cancelled
    account_suspended account_reinstated
    invitation_created invitation_revoked
    second_factor_reset password_setup_sent
  ].freeze

  ADDED_ACTION = "password_setup_sent"

  def up
    remove_check_constraint :admin_events, name: "admin_events_action"
    add_check_constraint :admin_events,
                         "action IN (#{ACTIONS.map { |action| "'#{action}'" }.join(', ')})",
                         name: "admin_events_action"
  end

  def down
    remove_check_constraint :admin_events, name: "admin_events_action"
    add_check_constraint :admin_events,
                         "action IN (#{(ACTIONS - [ ADDED_ACTION ]).map { |action| "'#{action}'" }.join(', ')})",
                         name: "admin_events_action"
  end
end
