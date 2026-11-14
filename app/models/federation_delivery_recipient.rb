# frozen_string_literal: true

require "uri"

class FederationDeliveryRecipient < ApplicationRecord
  STATUSES = %w[pending authorized withdrawn].freeze

  belongs_to :delivery, class_name: "FederationDelivery", inverse_of: :recipients

  validates :actor_uri, presence: true, uniqueness: { scope: :delivery_id }
  validates :status, inclusion: { in: STATUSES }
  validate :actor_uri_is_absolute

  scope :authorized, -> { where(status: "authorized") }

  def authorized? = status == "authorized"
  def withdrawn? = status == "withdrawn"

  def authorize!
    update!(status: "authorized") unless authorized?
    self
  end

  def withdraw!
    update!(status: "withdrawn") unless withdrawn?
    self
  end

  private

  def actor_uri_is_absolute
    parsed = URI.parse(actor_uri.to_s)
    valid = parsed.scheme.in?(%w[http https]) && parsed.host.present? && parsed.userinfo.blank?
    errors.add(:actor_uri, :invalid) unless valid
  rescue URI::InvalidURIError, URI::InvalidComponentError
    errors.add(:actor_uri, :invalid)
  end
end
