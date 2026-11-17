# frozen_string_literal: true

# One automatic publication of one imported workout for one audience
# (docs/dev/AUTO-PUBLISHING.md). The row is created at import when the account has
# an automatic publishing profile for that audience: `waiting` until every
# enrichment of the workout has settled, then `published` (immediately or
# inside the profile's safety delay), `skipped` with the reason nothing was
# published, or `failed` when publishing was refused or the enrichments never
# settled. It is owner-only bookkeeping: it never enters a snapshot and never
# federates.
class WorkoutAutoPublication < ApplicationRecord
  STATUSES = %w[waiting published skipped failed].freeze
  # Only recent activities are published by themselves: an old recording
  # imported today is history, not news.
  RECENT_WINDOW = 7.days
  # A file batch above this many entries is an archive, not a new outing.
  BULK_FILE_ENTRIES = 5
  # Enrichments that have not settled by then never will without help: the
  # owner is told to publish by hand.
  ENRICHMENT_DEADLINE = 6.hours
  SKIP_REASONS = %w[
    stale commute sport bulk_import already_published profile_disabled profile_unavailable
    cancelled_by_owner no_geometry
  ].freeze
  FAIL_REASONS = %w[publication_refused enrichment_timeout error].freeze
  # The reasons that come from the import itself, decided once at creation.
  IMPORT_SKIP_REASONS = %w[stale commute sport bulk_import].freeze

  belongs_to :workout
  belongs_to :publishing_profile, optional: true
  belongs_to :workout_publication, optional: true

  validates :audience, inclusion: { in: PublishingProfile::AUDIENCES }
  validates :status, inclusion: { in: STATUSES }
  validates :reason, inclusion: { in: SKIP_REASONS }, if: :skipped?
  validates :reason, inclusion: { in: FAIL_REASONS }, if: :failed?
  validates :deadline_at, presence: true

  scope :waiting, -> { where(status: "waiting") }
  scope :overdue, ->(now = Time.current) { waiting.where(deadline_at: ..now) }

  STATUSES.each do |value|
    define_method(:"#{value}?") { status == value }
  end

  def settle!(status, reason: nil, detail: nil, publication: nil, at: Time.current)
    update!(status:, reason:, detail: detail&.to_s&.truncate(500), workout_publication: publication, settled_at: at)
  end

  def overdue?(now = Time.current) = waiting? && deadline_at <= now
end
