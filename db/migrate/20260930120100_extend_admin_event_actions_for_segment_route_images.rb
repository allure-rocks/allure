# frozen_string_literal: true

# docs/dev/DERIVATIONS.md: the operator's derived-data maintenance gains a
# segment-image sweep. AdminEvent::ACTIONS is mirrored by a checked constraint,
# so the allowlist must be extended in the database too. Historical actions stay
# allowed: the audit log is append-only.
class ExtendAdminEventActionsForSegmentRouteImages < ActiveRecord::Migration[8.1]
  ACTIONS = %w[
    domain_blocked domain_unblocked actor_blocked actor_unblocked
    peer_policy_set peer_policy_removed media_retried
    job_retried job_discarded jobs_retried jobs_discarded
    queue_paused queue_resumed analysis_backfill_enqueued
    elevation_backfill_enqueued places_backfill_enqueued
    import_redetection_enqueued workouts_rebuild_enqueued route_images_backfill_enqueued
    segment_route_images_backfill_enqueued
    publication_withdrawn publication_schedule_cancelled
    account_suspended account_reinstated
    invitation_created invitation_revoked
  ].freeze

  ADDED_ACTION = "segment_route_images_backfill_enqueued"

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
