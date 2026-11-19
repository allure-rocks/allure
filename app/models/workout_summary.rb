# frozen_string_literal: true

# One assistant-written summary of a workout (docs/dev/AI.md). Owner-only: it
# never enters a publication, a federation object or a programmatic answer.
# The row keeps the facts it was written from, so a regeneration can tell
# whether they changed and the deferred conversation can start there.
class WorkoutSummary < ApplicationRecord
  STATUSES = %w[pending ready failed].freeze
  ERROR_CODES = %w[rejected invalid unavailable].freeze

  belongs_to :workout, inverse_of: :assistant_summary

  enum :status, STATUSES.index_with(&:itself)

  validates :workout_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :locale, presence: true
  validates :version, :requests_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :last_error, inclusion: { in: ERROR_CODES }, allow_nil: true
  validate :json_shapes

  # A generation is settled once it produced text or a final failure: the
  # recovery sweep only retries a pending row, never a ready or failed one.
  def settled? = !pending?

  private

  def json_shapes
    errors.add(:facts, :invalid) unless facts.is_a?(Array)
    errors.add(:sentences, :invalid) unless sentences.is_a?(Array)
  end
end
