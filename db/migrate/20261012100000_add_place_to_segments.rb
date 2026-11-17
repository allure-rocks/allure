# frozen_string_literal: true

# docs/dev/SEGMENTS.md: the nearby place the segment index shows beside each
# course, reverse-geocoded once from the course midpoint. Existing rows start
# `pending` so the audited backfill finds them; the place never federates.
class AddPlaceToSegments < ActiveRecord::Migration[8.1]
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
  ].freeze
  ADDED_ACTION = "segment_places_backfill_enqueued"

  def up
    add_column :segments, :place_name, :string, limit: 120
    add_column :segments, :place_status, :string, null: false, default: "pending"
    add_column :segments, :place_geocoded_at, :datetime
    add_check_constraint :segments,
                         "place_status IN ('pending', 'ready', 'unavailable', 'failed')",
                         name: "segments_place_status"
    add_index :segments, %i[place_status id], name: "index_segments_on_place_status_and_id"
    replace_constraint(PREVIOUS_ACTIONS + [ ADDED_ACTION ])
  end

  def down
    replace_constraint(PREVIOUS_ACTIONS)
    remove_index :segments, name: "index_segments_on_place_status_and_id"
    remove_check_constraint :segments, name: "segments_place_status"
    remove_column :segments, :place_geocoded_at
    remove_column :segments, :place_status
    remove_column :segments, :place_name
  end

  private

  def replace_constraint(values)
    remove_check_constraint :admin_events, name: "admin_events_action"
    add_check_constraint :admin_events, "action IN (#{values.map { "'#{it}'" }.join(', ')})", name: "admin_events_action"
  end
end
