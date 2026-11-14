# frozen_string_literal: true

# Adds the terrain-elevation backfill maintenance action to the operator audit
# log (PLAN_ELEVATION.md §7).
class AddElevationBackfillToAdminEvents < ActiveRecord::Migration[8.1]
  ACTIONS = %w[
    domain_blocked domain_unblocked actor_blocked actor_unblocked
    peer_policy_set peer_policy_removed media_retried
    job_retried job_discarded jobs_retried jobs_discarded
    queue_paused queue_resumed analysis_backfill_enqueued
    elevation_backfill_enqueued
    publication_withdrawn
    account_suspended account_reinstated
    invitation_created invitation_revoked
  ].freeze

  PREVIOUS_ACTIONS = %w[
    domain_blocked domain_unblocked actor_blocked actor_unblocked
    peer_policy_set peer_policy_removed media_retried
    job_retried job_discarded jobs_retried jobs_discarded
    queue_paused queue_resumed analysis_backfill_enqueued
    publication_withdrawn
    account_suspended account_reinstated
    invitation_created invitation_revoked
  ].freeze

  def up
    replace_action_constraint(ACTIONS)
  end

  def down
    replace_action_constraint(PREVIOUS_ACTIONS)
  end

  private

  def replace_action_constraint(actions)
    remove_check_constraint :admin_events, name: "admin_events_action"
    add_check_constraint :admin_events,
                         "action::text = ANY (ARRAY[#{actions.map { |action| "'#{action}'::character varying" }.join(', ')}]::text[])",
                         name: "admin_events_action"
  end
end
