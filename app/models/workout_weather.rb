# frozen_string_literal: true

# Historical weather met along one workout (PLAN_WEATHER.md §4). Owner-only:
# only `summary` may enter a publication snapshot, and only when the profile
# shares it.
class WorkoutWeather < ApplicationRecord
  STATUSES = %w[pending ready unavailable failed].freeze
  ENDPOINTS = %w[forecast archive].freeze

  belongs_to :workout, inverse_of: :weather

  enum :status, STATUSES.index_with(&:itself)

  validates :workout_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :endpoint, inclusion: { in: ENDPOINTS }, allow_nil: true
  validates :fetch_version, :analysis_version, :requests_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :json_shapes

  scope :fetched_since, ->(time) { where(fetched_at: time..) }

  # Every terminal state counts as settled: waiting will not improve a failure.
  def settled? = !pending?

  def series_values = Array(series).map { |row| Allure::Weather::Series::Row.from_h(row) }

  private

  def json_shapes
    errors.add(:samples, :invalid) unless samples.is_a?(Array)
    errors.add(:responses, :invalid) unless responses.is_a?(Array)
    errors.add(:series, :invalid) unless series.is_a?(Array)
    errors.add(:exposure, :invalid) unless exposure.is_a?(Hash)
    errors.add(:summary, :invalid) unless summary.is_a?(Hash)
  end
end
