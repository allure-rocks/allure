# frozen_string_literal: true

# One voluntary contribution to the instance operator (PLAN_FUNDING.md). The
# provider owns the payment; this row only records its verified result. An
# unmatched row has no user until the operator attaches it.
class FundingContribution < ApplicationRecord
  STATUSES = %w[active revoked].freeze
  TIER_RANK = Allure::Funding::TIERS.each_with_index.to_h { |tier, index| [ tier, index ] }.freeze
  METADATA_MAX_BYTES = 4_000

  belongs_to :user, optional: true
  belongs_to :funding_subscription, optional: true
  has_many :funding_reversals, dependent: :destroy

  normalizes :provider, with: ->(value) { value.to_s.strip.downcase }
  normalizes :tier, with: ->(value) { value.to_s.strip.downcase }
  normalizes :status, with: ->(value) { value.to_s.strip.downcase }
  normalizes :external_id, with: ->(value) { value.to_s.strip }
  normalizes :currency, with: ->(value) { value.to_s.strip.upcase.presence }

  before_validation :assign_external_id, on: :create
  before_validation :assign_manual_period

  validates :user, presence: true, if: -> { provider == "manual" }
  validates :provider, presence: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :tier, inclusion: { in: Allure::Funding::TIERS }
  validates :external_id, presence: true, length: { maximum: 255 }, uniqueness: { scope: :provider }
  validates :status, inclusion: { in: STATUSES }
  validates :paid_at, :starts_at, :expires_at, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }, allow_nil: true
  validate :period_is_positive
  validate :metadata_is_bounded_object
  validate :subscription_matches_payment

  scope :current, ->(at = Time.current) { where(status: "active").where("starts_at <= ? AND expires_at > ?", at, at) }
  scope :latest_first, -> { order(paid_at: :desc, id: :desc) }

  def current?(at = Time.current)
    status == "active" && starts_at.present? && expires_at.present? && starts_at <= at && at < expires_at
  end

  def upcoming?(at = Time.current) = starts_at.present? && starts_at > at

  def expired?(at = Time.current) = expires_at.present? && expires_at <= at

  def revoked? = status == "revoked"

  def effective_status(at = Time.current)
    return "revoked" if revoked?
    return "expired" if expired?(at)
    return "upcoming" if upcoming?(at)

    "active"
  end

  def revoke! = update!(status: "revoked")

  private

  def assign_external_id
    self.external_id ||= "manual-#{SecureRandom.uuid}" if provider == "manual"
  end

  def assign_manual_period
    return unless provider == "manual" && paid_at.present?
    return unless new_record? || will_save_change_to_paid_at?

    self.starts_at = paid_at
    self.expires_at = paid_at + 1.year
  end

  def period_is_positive
    return if starts_at.blank? || expires_at.blank? || expires_at > starts_at

    errors.add(:expires_at, :invalid)
  end

  def subscription_matches_payment
    return unless funding_subscription

    if provider == "manual" || provider != funding_subscription.provider || user != funding_subscription.user
      errors.add(:funding_subscription, :invalid)
    end
  end

  def metadata_is_bounded_object
    unless metadata.is_a?(Hash)
      errors.add(:metadata, :invalid)
      return
    end

    errors.add(:metadata, :too_long, count: METADATA_MAX_BYTES) if metadata.to_json.bytesize > METADATA_MAX_BYTES
  end
end
