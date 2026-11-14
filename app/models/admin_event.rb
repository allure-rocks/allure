# frozen_string_literal: true

# One immutable row per operator mutation (PLAN_ADMIN.md). The audit log is the
# operator's answer to "who did this, and when"; events are never updated or
# deleted through the application. `metadata` stays aggregate and non-secret:
# no payloads, coordinates, keys, or remote HTML.
class AdminEvent < ApplicationRecord
  ACTIONS = %w[
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
    segment_terrain_elevation_backfill_enqueued
    heart_rate_backfill_enqueued
    route_suggestions_backfill_enqueued
    photo_quota_changed
    funding_granted funding_revoked funding_attached
  ].freeze

  belongs_to :user, optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :action, presence: true, inclusion: { in: ACTIONS }
  validate :metadata_is_an_object

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  before_update :forbid_update

  private

  def metadata_is_an_object
    errors.add(:metadata, :invalid) unless metadata.is_a?(Hash)
  end

  # An audit row is append-only: a corrected history is another event, not an
  # edit.
  def forbid_update
    raise ActiveRecord::ReadOnlyRecord, "admin events are immutable"
  end
end
