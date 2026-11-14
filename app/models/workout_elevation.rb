# frozen_string_literal: true

class WorkoutElevation < ApplicationRecord
  STATUSES = %w[pending ready partial unavailable failed].freeze
  ALGORITHM_VERSION = 1

  belongs_to :workout, inverse_of: :elevation

  enum :status, STATUSES.index_with(&:itself)

  validates :workout_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :algorithm_version, numericality: { only_integer: true, greater_than: 0 }
  validates :requests_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :samples_shape

  private

  def samples_shape
    errors.add(:samples, :invalid) unless samples.is_a?(Array)
  end
end
