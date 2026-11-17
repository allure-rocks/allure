# frozen_string_literal: true

# A derived smart lap: a contiguous slice of one workout detected from the
# track or from existing efforts. Sources are `loop` and `route` (projected
# segment efforts), `pause` (one lap per recording segment), and `climb`
# (detected from the elevation profile). Rows are rebuildable in one
# transaction by Laps::Rebuild and are display-only: never URL-addressable, no
# ShortUUID, and never part of a publication. See docs/dev/SMART-LAPS.md.
class DetectedLap < ApplicationRecord
  SOURCES = %w[loop route pause climb descent stop speed_interval power_interval].freeze
  LAP_SOURCES = %w[loop route pause].freeze
  ELEVATION_SOURCES = %w[climb descent].freeze
  EFFORT_SOURCES = %w[speed_interval power_interval].freeze

  belongs_to :workout, inverse_of: :detected_laps
  belongs_to :segment_effort, optional: true, inverse_of: :detected_laps

  scope :laps, -> { where(source: LAP_SOURCES) }
  scope :climbs, -> { where(source: "climb") }
  scope :descents, -> { where(source: "descent") }
  scope :stops, -> { where(source: "stop") }
  scope :efforts, -> { where(source: EFFORT_SOURCES) }
  scope :chronological, -> { order(:start_distance, :id) }

  validates :source, inclusion: { in: SOURCES }
  validates :number,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 },
            uniqueness: { scope: [ :workout_id, :source ] }
  validates :started_at, presence: true
  validates :elapsed_time, numericality: { only_integer: true, greater_than: 0 }
  validates :moving_time, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :distance, numericality: { greater_than_or_equal_to: 0 }
  validates :start_distance, numericality: { greater_than_or_equal_to: 0 }
  validates :end_distance, numericality: { greater_than_or_equal_to: 0 }
  validates :ascent, :descent, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :average_speed, :max_speed, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :average_pace, :average_heart_rate, :max_heart_rate,
            :average_cadence, :average_power, :max_power, :grade_adjusted_pace,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :average_grade, :max_grade, :climb_score,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :start_point_index, :end_point_index, :detector_version,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :name, length: { maximum: 120 }, allow_nil: true
  validate :moving_time_within_elapsed
  validate :end_point_follows_start_point
  validate :end_distance_follows_start_distance

  private

  def moving_time_within_elapsed
    return if moving_time.nil? || elapsed_time.nil?

    errors.add(:moving_time, :less_than_or_equal_to, count: elapsed_time) if moving_time > elapsed_time
  end

  def end_point_follows_start_point
    return if start_point_index.nil? || end_point_index.nil?

    errors.add(:end_point_index, :greater_than, count: start_point_index) if end_point_index <= start_point_index
  end

  def end_distance_follows_start_distance
    return if start_distance.nil? || end_distance.nil?

    errors.add(:end_distance, :greater_than_or_equal_to, count: start_distance) if end_distance < start_distance
  end
end
