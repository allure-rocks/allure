# frozen_string_literal: true

# One best effort over a standard distance inside a single workout, rebuilt
# from the stored track points by `BestEfforts::Rebuild`. Display-only: never
# URL-addressable and never federated. See docs/dev/BEST-EFFORTS.md.
class BestEffort < ApplicationRecord
  belongs_to :user, inverse_of: :best_efforts
  belongs_to :sport, inverse_of: :best_efforts
  belongs_to :workout, inverse_of: :best_efforts

  validates :distance_key, presence: true, uniqueness: { scope: :workout_id }
  validates :distance_meters, numericality: { greater_than: 0 }
  validates :duration_seconds, numericality: { only_integer: true, greater_than: 0 }
  validates :started_at, presence: true
  validates :start_offset_meters, :end_offset_meters,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :end_offset_follows_start_offset

  private

  def end_offset_follows_start_offset
    return if start_offset_meters.nil? || end_offset_meters.nil?

    errors.add(:end_offset_meters, :greater_than_or_equal_to, count: start_offset_meters) if end_offset_meters < start_offset_meters
  end
end
