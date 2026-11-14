# frozen_string_literal: true

class WorkoutToponymy < ApplicationRecord
  STATUSES = %w[pending ready partial unavailable failed].freeze

  belongs_to :workout, inverse_of: :toponymy

  enum :status, STATUSES.index_with(&:itself)

  validates :workout_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :algorithm_version, numericality: { only_integer: true, greater_than: 0 }
  validates :places_algorithm_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sampled_points_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :json_shapes

  private

  def json_shapes
    errors.add(:samples, :invalid) unless samples.is_a?(Array)
    errors.add(:markers, :invalid) unless markers.is_a?(Array)
    errors.add(:places, :invalid) unless places.is_a?(Array)
    errors.add(:start_place, :invalid) unless start_place.is_a?(Hash)
    errors.add(:finish_place, :invalid) unless finish_place.is_a?(Hash)
  end
end
