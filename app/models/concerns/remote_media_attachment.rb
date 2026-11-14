# frozen_string_literal: true

require "uri"

# The shared descriptor contract for received-note and received-course
# attachments. The remote-media services (fetch, verification, processing,
# purge, recovery, retry) talk to these attributes and methods instead of a
# concrete owner class, while the models stay separate
# (PLAN_SEGMENTS_FEDERATION.md §7.4).
module RemoteMediaAttachment
  extend ActiveSupport::Concern

  KINDS = %w[gpx route_image].freeze
  # A route image arrives in two variants, distinguished by `allure:theme`
  # (DESIGN.md §15.4). GPX rows carry the default `light`, which is
  # meaningless for them but keeps the descriptor key uniform.
  THEMES = %w[light dark].freeze
  STATUSES = %w[pending fetching cached failed unavailable purged].freeze

  included do
    scope :pending, -> { where(status: "pending") }
    scope :cached, -> { where(status: "cached") }
    scope :purged, -> { where(status: "purged") }

    validates :kind, inclusion: { in: RemoteMediaAttachment::KINDS }
    validates :theme, inclusion: { in: RemoteMediaAttachment::THEMES }
    validates :status, inclusion: { in: RemoteMediaAttachment::STATUSES }
    validates :remote_url, presence: true
    validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :remote_url_is_absolute
    validate :purged_has_no_blob
  end

  def pending? = status == "pending"
  def fetching? = status == "fetching"
  def cached? = status == "cached"
  def failed? = status == "failed"
  def unavailable? = status == "unavailable"
  def purged? = status == "purged"

  # The RemoteNote or RemoteSegment this descriptor belongs to. Each including
  # model declares only one of the two associations, so `try` resolves the
  # right owner without branching on the class.
  def owner = try(:remote_note) || try(:remote_segment)

  def source_domain = owner.source_domain

  private

  def remote_url_is_absolute
    parsed = URI.parse(remote_url.to_s)
    valid = parsed.scheme.in?(%w[http https]) && parsed.host.present? &&
      parsed.userinfo.blank? && parsed.fragment.blank?
    errors.add(:remote_url, :invalid) unless valid
  rescue URI::InvalidURIError, URI::InvalidComponentError
    errors.add(:remote_url, :invalid)
  end

  def purged_has_no_blob
    return unless status == "purged"

    errors.add(:blob, :present) if blob_id.present?
    errors.add(:content_digest, :present) if content_digest.present?
    errors.add(:byte_size, :present) if byte_size.present?
  end
end
