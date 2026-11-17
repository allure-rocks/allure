# frozen_string_literal: true

# The stored first response to a POST carrying an Idempotency-Key
# (docs/dev/API.md). Without a response status the request is still running.
# The body is encrypted at rest: a kept response may carry a secret shown
# once (a webhook's, at creation or rotation), which the column it is
# replayed from must not keep in clear.
class ApiIdempotencyKey < ApplicationRecord
  TTL = 24.hours
  REPLAYED_HEADERS = %w[Content-Type Location].freeze

  belongs_to :api_token

  encrypts :response_body

  validates :key, presence: true, length: { maximum: 255 }
  validates :request_digest, format: { with: /\A\h{64}\z/ }
  validates :expires_at, presence: true

  scope :live, ->(now = Time.current) { where("expires_at > ?", now) }
  scope :expired, ->(now = Time.current) { where(expires_at: ..now) }

  def completed? = response_status.present?
end
