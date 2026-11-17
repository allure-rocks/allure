# frozen_string_literal: true

# An account's link to one remote provider (docs/dev/REMOTE-IMPORTS.md). The
# row is stable across re-links: unlinking wipes the credentials but keeps the
# row, so the external ids of what it imported keep deduplicating.
#
# `credentials` is one encrypted JSON object holding the provider's tokens and,
# for at most `PENDING_LIFETIME`, what a link in progress needs (the
# password, Garmin's MFA cookies). It is never logged, rendered, or passed to a job.
class ImportConnection < ApplicationRecord
  PROVIDERS = Allure::RemoteImports::Config.providers.freeze
  STATUSES = %w[pending mfa_pending linked expired revoked unlinking unlinked].freeze
  PENDING_STATUSES = %w[pending mfa_pending].freeze
  RELINK_STATUSES = %w[expired revoked].freeze
  REGIONS = %w[com cn].freeze
  PENDING_LIFETIME = 5.minutes
  # The Solid Queue concurrency group of every job that uses the tokens.
  CONCURRENCY_GROUP = "ImportConnection"

  serialize :credentials, coder: JSON
  encrypts :credentials

  belongs_to :user
  belongs_to :fallback_sport, class_name: "Sport", optional: true
  has_many :workouts, dependent: :nullify
  has_many :equipments, dependent: :nullify
  has_many :import_batches, class_name: "WorkoutImportBatch", dependent: :nullify

  validates :provider, inclusion: { in: PROVIDERS }, uniqueness: { scope: :user_id }
  validates :status, inclusion: { in: STATUSES }
  validates :region, inclusion: { in: REGIONS }
  validates :pending_expires_at, presence: true, if: :pending?
  validate :credentials_are_an_object

  # A provider whose listing mixes real workouts with bare detections (Withings
  # fed by Apple Health, §7c.3) imports positioned sessions only from the
  # start: the flag is set on creation through the `:route_filter` capability.
  before_validation on: :create do
    self.positioned_only = true if ImportConnections::Providers.supports?(provider, :route_filter)
  end

  scope :linked, -> { where(status: "linked") }

  after_initialize { self.credentials ||= {} }

  def self.for(user, provider)
    user.import_connections.find_or_initialize_by(provider: provider.to_s)
  end

  def source = Allure::ImportSources.for(provider)

  def enabled? = Allure::RemoteImports::Config.enabled?(provider)

  def linked? = status == "linked"

  def pending? = PENDING_STATUSES.include?(status)

  def needs_relink? = RELINK_STATUSES.include?(status)

  def unlinking? = status == "unlinking"

  # Never linked, or unlinked since: the card offers the link form.
  def disconnected? = new_record? || status == "unlinked"

  def pending_expired?(now = Time.current) = pending? && pending_expires_at <= now

  # A connection jobs may use: linked, and its provider still enabled.
  def usable? = linked? && enabled?

  def credential(key) = credentials.to_h[key.to_s]

  # Batches a provider session left queued when it ended (Withings's day,
  # docs/dev/REMOTE-IMPORTS.md): the next link resumes them.
  def interrupted_batches = import_batches.where(status: "queued")

  def interrupted_entries_count
    WorkoutImportEntry.where(batch: interrupted_batches, status: %w[queued processing]).count
  end

  private

  def credentials_are_an_object
    errors.add(:credentials, :invalid) unless credentials.is_a?(Hash)
  end
end
