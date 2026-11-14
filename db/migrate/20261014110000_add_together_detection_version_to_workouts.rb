# frozen_string_literal: true

# PLAN_TOGETHER.md §8, slice 3d: each recording remembers the detector version
# it was compared with, so the audited history backfill counts what is left
# and a rerun is a no-op (PLAN_DERIVATIONS.md: one generation marker per
# derivation). Existing recordings start at 0, pending.
class AddTogetherDetectionVersionToWorkouts < ActiveRecord::Migration[8.1]
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
  ].freeze
  ADDED_ACTION = "together_detection_backfill_enqueued"

  def up
    add_column :workouts, :together_detection_version, :integer, default: 0, null: false
    add_check_constraint :workouts, "together_detection_version >= 0", name: "workouts_together_detection_version"
    add_index :workouts, %i[together_detection_version id], where: "origin = 'import'",
                                                            name: "index_workouts_on_together_detection_version_and_id"
    replace_actions(PREVIOUS_ACTIONS + [ ADDED_ACTION ])
  end

  def down
    replace_actions(PREVIOUS_ACTIONS)
    remove_index :workouts, name: "index_workouts_on_together_detection_version_and_id"
    remove_check_constraint :workouts, name: "workouts_together_detection_version"
    remove_column :workouts, :together_detection_version
  end

  private

  def replace_actions(values)
    remove_check_constraint :admin_events, name: "admin_events_action"
    add_check_constraint :admin_events, "action IN (#{values.map { "'#{it}'" }.join(', ')})", name: "admin_events_action"
  end
end
