# frozen_string_literal: true

# One contiguous GPX <trkseg>: a recording segment between two pauses.
# Not to be confused with `Segment` (PLAN_SEGMENTS.md), which is a reusable,
# leaderboarded portion of a course.
#
# A segment of a positionless recording (PLAN_NO_GPS.md) has no `geom` and no
# coordinates in its points; `positioned?` tells the two apart.
class TrackSegment < ApplicationRecord
  belongs_to :workout, inverse_of: :track_segments

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, uniqueness: { scope: :workout_id }
  validates :started_at, :points, presence: true
  validates :duration, :moving_time, :pause_time, :points_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :distance, :ascent, :descent, :average_speed,
            numericality: { greater_than_or_equal_to: 0 }
  validates :max_speed, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :average_pace, :best_pace, :grade_adjusted_pace,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :average_heart_rate, :max_heart_rate, :average_cadence, :max_cadence,
            :average_power, :max_power,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :duration_components_are_consistent
  validate :point_data_is_consistent
  validate :point_coordinates_are_valid

  # A positioned segment has a LineString; a positionless one has none and
  # must not pretend otherwise (PLAN_NO_GPS.md §5).
  def positioned? = !geom.nil?

  private

  def duration_components_are_consistent
    return unless duration && moving_time && pause_time

    errors.add(:moving_time, :less_than_or_equal_to, count: duration) if moving_time > duration
    errors.add(:pause_time, :invalid) unless pause_time == duration - moving_time
  end

  def point_data_is_consistent
    return unless points.is_a?(Array) && points_count

    errors.add(:points_count, :invalid) unless points_count >= 2 && points.length == points_count
    errors.add(:geom, :invalid) if geom && geom.num_points < 2
  end

  # Coordinates are all-or-nothing, and they follow the geometry: a
  # positioned segment serialized every point with a fix, a positionless one
  # with none.
  def point_coordinates_are_valid
    return unless points.is_a?(Array)

    valid = points.all? do |point|
      longitude = point[Allure::Gpx::PointSerializer::KEY_LONGITUDE] if point.is_a?(Hash)
      latitude = point[Allure::Gpx::PointSerializer::KEY_LATITUDE] if point.is_a?(Hash)
      if positioned?
        longitude.is_a?(Numeric) && latitude.is_a?(Numeric) &&
          longitude.to_f.finite? && latitude.to_f.finite? &&
          longitude.between?(-180, 180) && latitude.between?(-90, 90)
      else
        longitude.nil? && latitude.nil?
      end
    end
    errors.add(:points, :invalid) unless valid
  end
end
