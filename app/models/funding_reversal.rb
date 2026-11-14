# frozen_string_literal: true

# One verified reversal signal against a recorded contribution (PLAN_FUNDING.md
# §3, PAY-105): a refund or a dispute, resolved through authenticated provider
# read-back to the original paid invoice. Reversals never rewrite the
# contribution — the badge-after-refund policy is unchanged and only the
# operator's manual revocation removes a badge — they give the operator the
# durable, idempotent facts for review: identity, kind, outcome, amount.
class FundingReversal < ApplicationRecord
  KINDS = %w[refund dispute].freeze
  STATUSES = %w[succeeded failed open won lost].freeze

  belongs_to :funding_contribution

  normalizes :provider, with: ->(value) { value.to_s.strip.downcase }
  normalizes :external_id, with: ->(value) { value.to_s.strip }
  normalizes :kind, :status, with: ->(value) { value.to_s.strip.downcase }
  normalizes :currency, with: ->(value) { value.to_s.strip.upcase.presence }

  validates :provider, presence: true, format: { with: /\A[a-z0-9_]+\z/ }, exclusion: { in: %w[manual] }
  validates :external_id, presence: true, length: { maximum: 255 }, uniqueness: { scope: :provider }
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }, allow_nil: true
  validates :reported_at, presence: true
  validate :status_matches_kind

  scope :latest_first, -> { order(reported_at: :desc, id: :desc) }

  private

  def status_matches_kind
    allowed = kind == "refund" ? %w[succeeded failed] : %w[open won lost]
    errors.add(:status, :invalid) if allowed.exclude?(status)
  end
end
