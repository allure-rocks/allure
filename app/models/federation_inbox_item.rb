# frozen_string_literal: true

require "uri"

class FederationInboxItem < ApplicationRecord
  STATUSES = %w[pending processing processed rejected failed].freeze
  TERMINAL_STATUSES = %w[processed rejected failed].freeze
  MAX_ATTEMPTS = 10
  RETRY_BASE = 5.minutes
  RETRY_CAP = 24.hours

  belongs_to :recipient_actor, class_name: "Actor", inverse_of: :inbox_items

  validates :activity_uri, presence: true, uniqueness: { scope: :recipient_actor_id }
  validates :raw_body_digest, format: { with: /\ASHA-256=[A-Za-z0-9+\/=]+\z/ }
  validates :raw, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :attempts, numericality: { only_integer: true, in: 0..MAX_ATTEMPTS }
  validates :remote_domain, presence: true, length: { maximum: 255 }
  validate :activity_uri_is_absolute
  validate :remote_domain_matches_actor_uri

  scope :due, ->(now = Time.current) {
    pending_status = where(status: "pending")
    pending_status.where(next_attempt_at: nil).or(pending_status.where(next_attempt_at: ..now))
  }

  def terminal? = TERMINAL_STATUSES.include?(status)
  def due?(now: Time.current) = pending? && (next_attempt_at.nil? || next_attempt_at <= now)
  def pending? = status == "pending"
  def processing? = status == "processing"
  def processed? = status == "processed"
  def rejected? = status == "rejected"
  def failed? = status == "failed"

  def claim!(now: Time.current)
    with_lock do
      return false unless due?(now:)
      if attempts >= MAX_ATTEMPTS
        update!(status: "failed", next_attempt_at: nil, last_error: "maximum attempts exceeded")
        return false
      end

      update!(status: "processing", attempts: attempts + 1, next_attempt_at: nil)
      true
    end
  end

  def mark_processed!(at: Time.current)
    update!(status: "processed", processed_at: at, next_attempt_at: nil, last_error: nil)
  end

  def reject!(reason:, at: Time.current)
    update!(status: "rejected", processed_at: at, next_attempt_at: nil, last_error: safe_error(reason))
  end

  def retry!(error:, now: Time.current)
    if attempts >= MAX_ATTEMPTS
      update!(status: "failed", next_attempt_at: nil, last_error: safe_error(error))
      return false
    end

    update!(status: "pending", next_attempt_at: now + retry_delay, last_error: safe_error(error))
    true
  end

  def retry_delay
    [ RETRY_BASE * (2**[ attempts - 1, 0 ].max), RETRY_CAP ].min
  end

  private

  def safe_error(error)
    message = error.respond_to?(:message) ? error.message : error.to_s
    message.to_s.gsub(/\s+/, " ").truncate(500)
  end

  def activity_uri_is_absolute
    parsed = URI.parse(activity_uri.to_s)
    valid = parsed.scheme.in?(%w[http https]) && parsed.host.present? && parsed.userinfo.blank?
    errors.add(:activity_uri, :invalid) unless valid
  rescue URI::InvalidURIError, URI::InvalidComponentError
    errors.add(:activity_uri, :invalid)
  end

  def remote_domain_matches_actor_uri
    return if actor_uri.blank? || remote_domain.blank?

    expected = Allure::Federation::Authority.domain(actor_uri)
    errors.add(:remote_domain, :invalid) unless expected == remote_domain
  end
end
