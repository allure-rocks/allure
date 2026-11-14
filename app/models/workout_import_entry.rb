# frozen_string_literal: true

class WorkoutImportEntry < ApplicationRecord
  STATUSES = %w[queued processing imported failed duplicate cancelled skipped].freeze
  TERMINAL_STATUSES = %w[imported failed duplicate cancelled skipped].freeze
  # `manual` is written when the owner changes the sport by hand, and
  # `declared` when the activity type the athlete chose elsewhere decided it
  # (PLAN_STRAVA_ARCHIVE.md §4), so the re-detection backfill never overwrites
  # a human decision (PLAN_VIRTUAL.md §6).
  SPORT_SOURCES = %w[detected declared fallback unknown manual].freeze
  # Why a remote activity was not imported (PLAN_REMOTE_IMPORTS.md §5.2).
  SKIP_REASONS = %w[no_geometry unsupported_sport no_file].freeze

  belongs_to :batch,
            class_name: "WorkoutImportBatch",
            inverse_of: :entries
  belongs_to :workout, optional: true

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :source_key, :source_name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :sport_source, inclusion: { in: SPORT_SOURCES }
  validates :skip_reason, inclusion: { in: SKIP_REASONS }, if: :skipped?
  validates :skip_reason, absence: true, unless: :skipped?
  validate :metadata_is_an_object

  def terminal? = TERMINAL_STATUSES.include?(status)
  def skipped? = status == "skipped"
  def fallback_sport? = sport_source == "fallback"

  private

  def metadata_is_an_object
    errors.add(:metadata, :invalid) unless metadata.is_a?(Hash)
  end
end
