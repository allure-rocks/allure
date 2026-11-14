# frozen_string_literal: true

# Provider lifecycle state, never a badge entitlement. Only the associated
# paid invoice periods count, even if this subscription has since ended.
class FundingSubscription < ApplicationRecord
  STATUSES = %w[incomplete active past_due paused canceled].freeze
  LIVE_STATUSES = (STATUSES - %w[canceled]).freeze

  belongs_to :user, optional: true
  has_many :funding_contributions, dependent: :restrict_with_exception

  normalizes :provider, :external_id, :customer_id, with: ->(value) { value.to_s.strip }
  normalizes :tier, :status, with: ->(value) { value.to_s.strip.downcase }

  validates :provider, presence: true, format: { with: /\A[a-z0-9_]+\z/ }, exclusion: { in: %w[manual] }
  validates :external_id, presence: true, length: { maximum: 255 }, uniqueness: { scope: :provider }
  validates :customer_id, presence: true, length: { maximum: 255 }
  validates :tier, inclusion: { in: Allure::Funding::TIERS }
  validates :status, inclusion: { in: STATUSES }
  validates :cancel_at_period_end, inclusion: { in: [ true, false ] }
  validate :matched_account_cannot_change

  scope :live, -> { where(status: LIVE_STATUSES) }
  scope :unmatched, -> { where(user_id: nil) }

  def live? = LIVE_STATUSES.include?(status)

  private

  def matched_account_cannot_change
    errors.add(:user, :invalid) if user_id_in_database.present? && will_save_change_to_user_id?
  end
end
