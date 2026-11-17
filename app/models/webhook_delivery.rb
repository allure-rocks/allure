# frozen_string_literal: true

# One event's delivery chain to one endpoint (docs/dev/API.md): pending
# through its retries, then succeeded, failed (the endpoint answered 410), or
# abandoned once the retries ran out or the endpoint went away.
class WebhookDelivery < ApplicationRecord
  include HasShortId

  STATUSES = %w[pending succeeded failed abandoned].freeze
  # Waits after the first, second… failed attempt; about 21 hours in all.
  RETRY_DELAYS = [ 1.minute, 5.minutes, 30.minutes, 2.hours, 6.hours, 12.hours ].freeze

  belongs_to :webhook_event
  belongs_to :webhook_endpoint
  belongs_to :redelivery_of, class_name: "WebhookDelivery", optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :due, ->(now = Time.current) {
    pending.where(next_attempt_at: nil).or(pending.where(next_attempt_at: ..now))
  }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def pending? = status == "pending"
end
