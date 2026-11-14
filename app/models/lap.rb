# frozen_string_literal: true

# One file-recorded lap: a FIT `lap` message or a GPX `<lap>` element, parsed
# at import and persisted in order. Laps are file-recorded and display-only — never
# URL-addressable, no ShortUUID — and a workout simply shows them (in preference
# to detected loops) on its own page. See PLAN_M3.md section 6.1.
class Lap < ApplicationRecord
  belongs_to :workout, inverse_of: :laps

  validates :number, :started_at, :elapsed_time, :moving_time, presence: true
  validates :number, numericality: { only_integer: true, greater_than_or_equal_to: 1 },
            uniqueness: { scope: :workout_id }
  validates :elapsed_time, :moving_time, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :distance, :ascent, :descent, :average_speed, :max_speed,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :average_pace, :average_heart_rate, :max_heart_rate, :average_cadence, :average_power,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :moving_time_within_elapsed

  private

  def moving_time_within_elapsed
    return if moving_time.nil? || elapsed_time.nil?

    errors.add(:moving_time, :invalid) unless moving_time.between?(0, elapsed_time)
  end
end
