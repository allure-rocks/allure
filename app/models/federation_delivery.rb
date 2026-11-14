# frozen_string_literal: true

require "uri"

class FederationDelivery < ApplicationRecord
  STATUSES = %w[pending delivering reconciling delivered retrying cancelled failed].freeze
  TERMINAL_STATUSES = %w[delivered cancelled failed].freeze
  MAX_ATTEMPTS = 10
  RETRY_BASE = 5.minutes
  RETRY_CAP = 24.hours
  LEASE_DURATION = 5.minutes

  belongs_to :outbox_event, class_name: "FederationOutboxEvent", inverse_of: :deliveries
  has_many :recipients, class_name: "FederationDeliveryRecipient", inverse_of: :delivery,
           dependent: :destroy

  validates :inbox_url, presence: true, uniqueness: { scope: :outbox_event_id }
  validates :status, inclusion: { in: STATUSES }
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :inbox_url_is_absolute

  scope :due, ->(now = Time.current) {
    where(status: %w[pending retrying]).where("next_attempt_at IS NULL OR next_attempt_at <= ?", now)
      .or(where(status: "delivering").where("lease_until < ?", now))
  }

  def terminal? = TERMINAL_STATUSES.include?(status)
  def retryable? = %w[pending retrying].include?(status)
  def delivering? = status == "delivering"
  def retrying? = status == "retrying"
  def delivered? = status == "delivered"
  def cancelled? = status == "cancelled"
  def failed? = status == "failed"
  def due?(now: Time.current)
    (retryable? && (next_attempt_at.nil? || next_attempt_at <= now)) ||
      (status == "delivering" && lease_until.present? && lease_until < now)
  end

  def claim!(now: Time.current, lease_for: LEASE_DURATION)
    with_lock do
      return false unless due?(now:)
      if attempts >= MAX_ATTEMPTS
        update!(status: "failed", next_attempt_at: nil, lease_until: nil, last_error: "maximum attempts exceeded")
        return false
      end

      update!(
        status: "delivering",
        attempts: attempts + 1,
        lease_until: now + lease_for,
        next_attempt_at: nil
      )
      true
    end
  end

  def mark_delivered!(response_status:, at: Time.current)
    update!(
      status: "delivered",
      last_response_status: response_status,
      delivered_at: at,
      lease_until: nil,
      next_attempt_at: nil,
      last_error: nil
    )
  end

  def mark_reconciling!(response_status:)
    update!(status: "reconciling", last_response_status: response_status, lease_until: nil)
  end

  def retry!(error:, response_status: nil, now: Time.current)
    if attempts >= MAX_ATTEMPTS
      update!(status: "failed", last_response_status: response_status, lease_until: nil, last_error: safe_error(error))
      return false
    end

    update!(
      status: "retrying",
      last_response_status: response_status,
      next_attempt_at: now + retry_delay,
      lease_until: nil,
      last_error: safe_error(error)
    )
    true
  end

  def cancel!(reason: nil, response_status: nil)
    update!(
      status: "cancelled",
      last_response_status: response_status,
      lease_until: nil,
      next_attempt_at: nil,
      last_error: reason && safe_error(reason)
    )
  end

  def fail!(error:, response_status: nil)
    update!(
      status: "failed",
      last_response_status: response_status,
      lease_until: nil,
      next_attempt_at: nil,
      last_error: safe_error(error)
    )
  end

  def retry_delay
    [ RETRY_BASE * (2**[ attempts - 1, 0 ].max), RETRY_CAP ].min
  end

  private

  def safe_error(error)
    message = error.respond_to?(:message) ? error.message : error.to_s
    message.to_s.gsub(/\s+/, " ").truncate(500)
  end

  def inbox_url_is_absolute
    parsed = URI.parse(inbox_url.to_s)
    valid = parsed.scheme.in?(%w[http https]) && parsed.host.present? && parsed.userinfo.blank? && parsed.fragment.blank?
    errors.add(:inbox_url, :invalid) unless valid
  rescue URI::InvalidURIError, URI::InvalidComponentError
    errors.add(:inbox_url, :invalid)
  end
end
