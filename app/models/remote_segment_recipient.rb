# frozen_string_literal: true

# One local actor's entitlement to one received course. Entitlements are what
# make recipient-aware reads possible: a followers-only course delivered for
# one account never appears for another (docs/dev/SEGMENTS-FEDERATION.md).
class RemoteSegmentRecipient < ApplicationRecord
  STATUSES = %w[active withdrawn].freeze
  WITHDRAWAL_REASONS = %w[unfollow rejected blocked deleted unreachable].freeze

  belongs_to :remote_segment, inverse_of: :recipients
  belongs_to :recipient_actor, class_name: "Actor", inverse_of: :remote_segment_recipients
  belongs_to :inbox_item, class_name: "FederationInboxItem", optional: true

  scope :active, -> { where(status: "active") }

  validates :status, inclusion: { in: STATUSES }
  validates :recipient_actor_id, uniqueness: { scope: :remote_segment_id }
  validates :withdrawal_reason, inclusion: { in: WITHDRAWAL_REASONS }, allow_nil: true
  validate :recipient_is_local
  validate :status_matches_withdrawn_at

  def active? = status == "active"
  def withdrawn? = status == "withdrawn"

  def withdraw!(reason:, at: Time.current)
    raise ArgumentError, "unknown withdrawal reason" unless WITHDRAWAL_REASONS.include?(reason.to_s)

    with_lock do
      return self if withdrawn?

      update!(status: "withdrawn", withdrawn_at: at, withdrawal_reason: reason.to_s)
    end
  end

  private

  def recipient_is_local
    errors.add(:recipient_actor, :invalid) if recipient_actor && !recipient_actor.local?
  end

  def status_matches_withdrawn_at
    errors.add(:withdrawn_at, :invalid) unless withdrawn? == withdrawn_at.present?
  end
end
