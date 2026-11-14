# frozen_string_literal: true

# One in-app notification for one account (PLAN_NOTIFICATIONS.md). The row is a
# small recipient-scoped record: `actor` is who caused it, `subject` is the
# relationship it describes, and `payload` stays an object reserved for kinds
# that need display data. A notification never carries coordinates, workout
# content, or remote HTML, and it is withdrawn when its relationship ends.
class Notification < ApplicationRecord
  KINDS = %w[
    follow_request follow_accepted publication_activated reaction
    participation_requested participation_suggested participation_confirmed
    participation_source_deleted participation_link_suggested
    comment import_connection_expired import_connection_revoked
    auto_published auto_publication_failed webhook_disabled
    account_export_ready funding_recorded
  ].freeze

  # The inbox is bounded per account: the oldest rows are pruned as new ones
  # arrive, so an inactive account never accumulates unbounded history.
  MAX_PER_USER = 100

  # Kinds that wait for the recipient to decide or repair something; the cap
  # never prunes them while they are unread.
  ACTIONABLE_KINDS = %w[
    follow_request participation_requested participation_suggested
    participation_link_suggested import_connection_expired
    auto_publication_failed webhook_disabled
  ].freeze

  belongs_to :user
  belongs_to :actor, class_name: "Actor", optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :kind, inclusion: { in: KINDS }
  validate :payload_is_an_object

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  scope :unread, -> { where(read_at: nil) }

  def read? = read_at.present?

  def mark_read!(at: Time.current)
    return self if read?

    update!(read_at: at)
  end

  private

  def payload_is_an_object
    errors.add(:payload, :invalid) unless payload.is_a?(Hash)
  end
end
