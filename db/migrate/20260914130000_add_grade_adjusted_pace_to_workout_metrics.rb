# frozen_string_literal: true

class AddGradeAdjustedPaceToWorkoutMetrics < ActiveRecord::Migration[8.1]
  def up
    add_column :workouts, :grade_adjusted_pace, :integer
    add_check_constraint :workouts, "grade_adjusted_pace IS NULL OR grade_adjusted_pace >= 0", name: "workouts_grade_adjusted_pace"

    add_column :track_segments, :grade_adjusted_pace, :integer
    add_check_constraint :track_segments, "grade_adjusted_pace IS NULL OR grade_adjusted_pace >= 0", name: "track_segments_grade_adjusted_pace"

    add_column :detected_laps, :grade_adjusted_pace, :integer
    add_check_constraint :detected_laps, "grade_adjusted_pace IS NULL OR grade_adjusted_pace >= 0", name: "detected_laps_grade_adjusted_pace"

    add_column :segment_efforts, :grade_adjusted_pace, :integer
    add_check_constraint :segment_efforts, "grade_adjusted_pace IS NULL OR grade_adjusted_pace >= 0", name: "segment_efforts_grade_adjusted_pace"
  end

  def down
    remove_check_constraint :workouts, name: "workouts_grade_adjusted_pace"
    remove_column :workouts, :grade_adjusted_pace

    remove_check_constraint :track_segments, name: "track_segments_grade_adjusted_pace"
    remove_column :track_segments, :grade_adjusted_pace

    remove_check_constraint :detected_laps, name: "detected_laps_grade_adjusted_pace"
    remove_column :detected_laps, :grade_adjusted_pace

    remove_check_constraint :segment_efforts, name: "segment_efforts_grade_adjusted_pace"
    remove_column :segment_efforts, :grade_adjusted_pace
  end
end
