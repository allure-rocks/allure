# frozen_string_literal: true

# One event emitted to an account's webhooks, its payload frozen at emission
# (PLAN_API.md §11.1). The `evt_` id is the envelope's `id` and the
# `webhook-id` header, the same for every attempt and every redelivery.
class WebhookEvent < ApplicationRecord
  include HasShortId

  ID_PREFIX = "evt_"
  API_VERSION = "v1"
  RETENTION = 30.days

  belongs_to :user
  has_many :deliveries, class_name: "WebhookDelivery", dependent: :delete_all, inverse_of: :webhook_event

  validates :event_type, :dedupe_key, :occurred_at, presence: true

  scope :prunable, ->(now = Time.current) { where(created_at: ...(now - RETENTION)) }

  def public_id = ID_PREFIX + to_param

  def self.find_by_public_id!(value)
    find_by_short_id!(value.to_s.delete_prefix(ID_PREFIX))
  end

  # The exact bytes every delivery of this event sends.
  def body
    @body ||= JSON.generate(
      id: public_id, type: event_type, created_at: occurred_at.utc.iso8601,
      api_version: API_VERSION, data: payload
    )
  end
end
