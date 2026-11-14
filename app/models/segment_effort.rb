# frozen_string_literal: true

class SegmentEffort < ApplicationRecord
  include HasShortId

  belongs_to :segment, inverse_of: :segment_efforts
  belongs_to :workout, inverse_of: :segment_efforts
  belongs_to :user, inverse_of: :segment_efforts
  belongs_to :sport, inverse_of: :segment_efforts
  has_many :detected_laps, dependent: :nullify, inverse_of: :segment_effort

  validates :uuid, uniqueness: true, allow_nil: true
  validates :occurrence_index,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            uniqueness: { scope: [ :segment_id, :workout_id ] }
  validates :started_at, presence: true
  validates :elapsed_time, numericality: { only_integer: true, greater_than: 0 }
  validates :moving_time, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :distance, :average_speed, :start_offset_meters, :deviation_meters,
            numericality: { greater_than_or_equal_to: 0 }
  validates :ascent, :descent, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :average_pace, :average_heart_rate, :max_heart_rate,
            :average_cadence, :average_power, :max_power, :grade_adjusted_pace,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :start_point_index, :end_point_index, :matcher_version,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :personal_best, :anonymous, inclusion: { in: [ true, false ] }
  validate :moving_time_does_not_exceed_elapsed_time
  validate :end_point_follows_start_point

  private

  def moving_time_does_not_exceed_elapsed_time
    return unless moving_time && elapsed_time

    errors.add(:moving_time, :less_than_or_equal_to, count: elapsed_time) if moving_time > elapsed_time
  end

  def end_point_follows_start_point
    return unless start_point_index && end_point_index

    errors.add(:end_point_index, :greater_than, count: start_point_index) if end_point_index <= start_point_index
  end
end
