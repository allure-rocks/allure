# frozen_string_literal: true

# A reviewable bulk operation over the owner's workouts
# (docs/dev/BULK-ACTIONS.md). A draft freezes the reviewed selection; confirming stores the validated
# parameters and hands the row to Workouts::BulkOperationJob, which walks the
# items in order. Quick actions never create a row.
class WorkoutBulkOperation < ApplicationRecord
  OPERATIONS = %w[sport_change delete].freeze
  STATUSES = %w[draft queued processing completed failed cancelled].freeze
  ACTIVE_STATUSES = %w[queued processing].freeze
  TERMINAL_STATUSES = %w[completed failed cancelled].freeze

  class InvalidParameters < StandardError; end
  class NotDraft < StandardError; end

  belongs_to :user
  has_many :items,
           class_name: "WorkoutBulkOperationItem",
           dependent: :destroy,
           inverse_of: :operation

  validates :operation, inclusion: { in: OPERATIONS }
  validates :status, inclusion: { in: STATUSES }

  scope :drafts, -> { where(status: "draft") }

  def terminal? = TERMINAL_STATUSES.include?(status)
  def active? = ACTIVE_STATUSES.include?(status)
  def draft? = status == "draft"
  def cancellation_requested? = cancellation_requested_at.present?

  # The list the operation was started from, when it is a local path. Stored
  # sanitized at creation; re-checked here so a tampered row can never become
  # an open redirect.
  def return_to
    path = parameters["return_to"].to_s
    path.start_with?("/") && !path.start_with?("//") ? path : nil
  end

  # One draft at a time: an abandoned review never blocks the next one, and a
  # frozen selection never lingers unreviewed.
  def self.start_draft!(user:, operation:, workout_ids:, return_to: nil)
    transaction do
      user.workout_bulk_operations.drafts.update_all(
        status: "cancelled", completed_at: Time.current, updated_at: Time.current
      )
      record = user.workout_bulk_operations.create!(
        operation:,
        status: "draft",
        parameters: return_to.present? ? { "return_to" => return_to } : {}
      )
      now = Time.current
      record.items.insert_all(
        workout_ids.map.with_index do |workout_id, index|
          { workout_id:, position: index, status: "queued", created_at: now, updated_at: now }
        end
      )
      record
    end
  end

  # Freezes the reviewed choices and queues the operation. A second confirm
  # (double submit, back button) is refused, never enqueued twice.
  def confirm!(sport_id: nil)
    with_lock do
      raise NotDraft unless draft?

      parameters = self.parameters
      if operation == "sport_change"
        sport = Sport.find_by(id: sport_id)
        raise InvalidParameters, :missing_sport unless sport

        parameters = parameters.merge("sport_id" => sport.id)
      end

      update!(status: "queued", parameters:)
    end
  end

  # A draft is cancelled outright; a running operation records the request and
  # the job stops between items.
  def cancel!
    with_lock do
      return false if terminal?

      if draft?
        items.where(status: "queued").update_all(status: "cancelled", updated_at: Time.current)
        update!(status: "cancelled", cancellation_requested_at: Time.current, completed_at: Time.current)
      else
        update!(cancellation_requested_at: Time.current)
      end
    end
    true
  end

  def start!
    update!(status: "processing", started_at: Time.current)
  end

  def complete!
    update!(status: "completed", completed_at: Time.current)
  end

  def mark_failed!
    update!(status: "failed", completed_at: Time.current)
  end

  def cancel_remaining!
    transaction do
      items.where(status: "queued").update_all(status: "cancelled", updated_at: Time.current)
      update!(status: "cancelled", completed_at: Time.current)
    end
  end

  def total_count = items.count
  def progress_counts = items.group(:status).count
  def processed_count = [ total_count - progress_counts.fetch("queued", 0), 0 ].max

  def progress_percentage
    total = total_count
    return 0 if total.zero?

    [ (processed_count * 100.0 / total).floor, 100 ].min
  end
end
