# frozen_string_literal: true

# One requested copy of an account's data (docs/dev/ACCOUNT.md): built by
# Users::ExportJob into a single ZIP, downloadable by its owner only for
# LIFETIME, then purged. One export runs at a time per account, and a new one
# may be requested once every COOLDOWN.
class AccountExport < ApplicationRecord
  include HasShortId

  STATUSES = %w[pending running ready failed expired].freeze
  IN_PROGRESS_STATUSES = %w[pending running].freeze
  LIFETIME = 7.days
  COOLDOWN = 24.hours

  belongs_to :user
  has_one_attached :archive, dependent: :purge_later

  validates :uuid, uniqueness: true, allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validate :counts_are_an_object

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :in_progress, -> { where(status: IN_PROGRESS_STATUSES) }
  scope :due_for_expiry, ->(now = Time.current) { where(status: "ready").where(expires_at: ..now) }

  def in_progress? = IN_PROGRESS_STATUSES.include?(status)

  def ready? = status == "ready"

  def downloadable?(now = Time.current) = ready? && expires_at.present? && expires_at > now && archive.attached?

  # The account may ask again once nothing runs and the last request is older
  # than the cooldown, whatever its outcome.
  def self.requestable_for?(user, now = Time.current)
    return false if user.account_exports.in_progress.exists?

    !user.account_exports.where(created_at: (now - COOLDOWN)..).exists?
  end

  def self.next_request_at(user)
    last = user.account_exports.newest_first.first
    last && (last.created_at + COOLDOWN)
  end

  def filename
    "allure-#{user.username}-#{(completed_at || created_at).utc.strftime('%Y%m%d')}.zip"
  end

  def expire!
    update!(status: "expired")
    archive.purge_later
  end

  private

  def counts_are_an_object
    errors.add(:counts, :invalid) unless counts.is_a?(Hash)
  end
end
