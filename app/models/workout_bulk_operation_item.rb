# frozen_string_literal: true

# One workout inside a durable bulk operation (PLAN_BULK_ACTIONS.md §4). The
# workout reference is nullified when a deletion operation removes it, so the
# report survives its own effect; `failure_code` is a stable key translated at
# render time, never a raw exception message.
class WorkoutBulkOperationItem < ApplicationRecord
  STATUSES = %w[queued modified skipped failed cancelled].freeze
  FAILURE_CODES = %w[missing_original_file reanalysis_failed workout_missing unknown].freeze

  belongs_to :operation,
             class_name: "WorkoutBulkOperation",
             foreign_key: :workout_bulk_operation_id,
             inverse_of: :items
  belongs_to :workout, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :failure_code, inclusion: { in: FAILURE_CODES }, allow_nil: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :queued, -> { where(status: "queued") }
  scope :in_order, -> { order(:position, :id) }

  def terminal? = status != "queued"

  def mark_modified! = update!(status: "modified", failure_code: nil)
  def mark_skipped!(code) = update!(status: "skipped", failure_code: code)
  def mark_failed!(code = "unknown") = update!(status: "failed", failure_code: code)
  def mark_cancelled! = update!(status: "cancelled")
end
