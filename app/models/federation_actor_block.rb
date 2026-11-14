# frozen_string_literal: true

require "uri"

class FederationActorBlock < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true

  # The host is case-insensitive, so the block is stored and queried with a
  # folded host; otherwise a peer could evade an actor block by serving the
  # same URI with different host casing.
  normalizes :actor_uri, with: ->(actor_uri) { Allure::Federation::Authority.normalize_uri(actor_uri) }

  validates :actor_uri, presence: true, uniqueness: true
  validate :actor_uri_is_absolute

  private

  def actor_uri_is_absolute
    parsed = URI.parse(actor_uri.to_s)
    valid = parsed.absolute? && parsed.host.present? && parsed.userinfo.blank? &&
      parsed.query.blank? && parsed.fragment.blank?
    errors.add(:actor_uri, :invalid) unless valid
  rescue URI::InvalidURIError, URI::InvalidComponentError
    errors.add(:actor_uri, :invalid)
  end
end
