# frozen_string_literal: true

class WorkoutImportBatch < ApplicationRecord
  include HasShortId

  STATUSES = %w[queued processing completed failed cancelled].freeze
  TERMINAL_STATUSES = %w[completed failed cancelled].freeze
  SOURCES = ([ "file", Allure::ImportSources::STRAVA_ARCHIVE.key ] + Allure::RemoteImports::Config.providers).freeze
  # `api`: uploaded through the REST API (docs/dev/API.md).
  TRIGGERS = %w[manual scheduled webhook api].freeze

  belongs_to :user
  # Required for an uploaded batch; a remote batch may rely on each file's own
  # sport and the connection's fallback (docs/dev/REMOTE-IMPORTS.md), a Strava
  # archive on each activity's declared type (PLAN_STRAVA_ARCHIVE.md §4).
  belongs_to :sport, optional: true
  belongs_to :import_connection, optional: true
  # The options card's gear (docs/dev/IMPORT-SOURCES.md): the importer attaches
  # it to every workout of the batch and keeps Equipment totals in step.
  has_and_belongs_to_many :equipments, join_table: "workout_import_batch_equipments"
  has_many :entries,
           class_name: "WorkoutImportEntry",
           dependent: :destroy,
           inverse_of: :batch
  has_many_attached :source_files, dependent: :purge_later

  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :sport, presence: true, if: :file?
  validates :import_connection, presence: true, if: :remote?, on: :create
  validates :title, length: { maximum: 255 }, allow_nil: true
  validates :notes, length: { maximum: 500 }, allow_nil: true
  validates :total_entries, :processed_entries, :imported_entries, :failed_entries,
            :duplicate_entries, :cancelled_entries, :skipped_entries, :source_bytes,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where.not(status: TERMINAL_STATUSES) }
  scope :terminal, -> { where(status: TERMINAL_STATUSES) }
  validate :range_is_ordered

  def terminal? = TERMINAL_STATUSES.include?(status)
  def active? = !terminal?
  def cancellation_requested? = cancellation_requested_at.present?
  def file? = source == "file"
  def remote? = import_source&.remote? || false
  def strava_archive? = source == Allure::ImportSources::STRAVA_ARCHIVE.key
  def paused?(now = Time.current) = paused_until.present? && paused_until > now
  def import_source = Allure::ImportSources.for(source)

  def progress_percentage
    return 0 if total_entries.zero?

    [ (processed_entries * 100.0 / total_entries).floor, 100 ].min
  end

  def refresh_progress!
    counts = entries.group(:status).count
    imported = counts.fetch("imported", 0)
    failed = counts.fetch("failed", 0)
    duplicate = counts.fetch("duplicate", 0)
    cancelled = counts.fetch("cancelled", 0)
    skipped = counts.fetch("skipped", 0)
    processed = imported + failed + duplicate + cancelled + skipped

    update_columns(
      total_entries: entries.count,
      processed_entries: processed,
      imported_entries: imported,
      failed_entries: failed,
      duplicate_entries: duplicate,
      cancelled_entries: cancelled,
      skipped_entries: skipped,
      updated_at: Time.current
    )
  end

  def cancel!
    update!(cancellation_requested_at: Time.current) if active? && !cancellation_requested?
  end

  # Each imported workout keeps its own copy of its original, so a finished
  # batch never reads its upload again (docs/dev/IMPORT-SOURCES.md).
  def release_sources!
    source_files.purge_later if source_files.attached?
  end

  private

  def range_is_ordered
    return if range_from.nil? || range_to.nil? || range_from <= range_to

    errors.add(:range_to, :invalid)
  end
end
