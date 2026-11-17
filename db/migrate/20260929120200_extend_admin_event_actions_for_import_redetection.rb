# frozen_string_literal: true

# docs/dev/VIRTUAL-PLATFORMS.md: the operator can enqueue the import re-detection sweep
# from /admin/jobs. AdminEvent::ACTIONS is mirrored by a checked constraint, so
# the allowlist must be extended in the database too.
class ExtendAdminEventActionsForImportRedetection < ActiveRecord::Migration[8.1]
  ACTIONS = %w[
    domain_blocked domain_unblocked actor_blocked actor_unblocked
    peer_policy_set peer_policy_removed media_retried
    job_retried job_discarded jobs_retried jobs_discarded
    queue_paused queue_resumed analysis_backfill_enqueued
    elevation_backfill_enqueued places_backfill_enqueued
    import_redetection_enqueued
    publication_withdrawn publication_schedule_cancelled
    account_suspended account_reinstated
    invitation_created invitation_revoked
  ].freeze

  def up
    remove_check_constraint :admin_events, name: "admin_events_action"
    add_check_constraint :admin_events,
                         "action IN (#{ACTIONS.map { |action| "'#{action}'" }.join(', ')})",
                         name: "admin_events_action"
  end

  def down
    remove_check_constraint :admin_events, name: "admin_events_action"
    add_check_constraint :admin_events,
                         "action IN (#{(ACTIONS - [ 'import_redetection_enqueued' ]).map { |action| "'#{action}'" }.join(', ')})",
                         name: "admin_events_action"
  end
end
