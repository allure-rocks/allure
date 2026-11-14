# frozen_string_literal: true

module Allure
  module Laps
    # One derived smart lap before it is persisted. Mirrors the
    # `detected_laps` row; `segment_effort_id` traces a loop or route lap back
    # to the effort it was projected from, and `name` is the geocoded label
    # written by Laps::Naming.
    Lap = Data.define(
      :source,
      :start_point_index,
      :end_point_index,
      :start_distance,
      :end_distance,
      :started_at,
      :elapsed_time,
      :moving_time,
      :distance,
      :ascent,
      :descent,
      :average_speed,
      :average_pace,
      :max_speed,
      :average_heart_rate,
      :max_heart_rate,
      :average_cadence,
      :average_power,
      :max_power,
      :grade_adjusted_pace,
      :average_grade,
      :max_grade,
      :climb_score,
      :segment_effort_id,
      :name
    ) do
      def initialize(source:, start_point_index:, end_point_index:, start_distance:, end_distance:,
                     started_at:, elapsed_time:, moving_time:, distance:,
                     ascent: nil, descent: nil, average_speed: nil, average_pace: nil, max_speed: nil,
                     average_heart_rate: nil, max_heart_rate: nil, average_cadence: nil,
                     average_power: nil, max_power: nil, grade_adjusted_pace: nil,
                     average_grade: nil, max_grade: nil, climb_score: nil,
                     segment_effort_id: nil, name: nil)
        super
      end

      def overlaps?(other)
        start_distance < other.end_distance && other.start_distance < end_distance
      end
    end
  end
end
