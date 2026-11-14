# frozen_string_literal: true

class WorkoutSegmentSelectionsController < ApplicationController
  before_action :set_owned_workout

  def show
    points = Allure::Gpx::ChartSeries.new(
      workout_started_at: @workout.started_at,
      segments: @workout.track_segments,
      include_index: true
    ).call

    response.headers["Cache-Control"] = "private, no-store"
    render json: { points: }
  end

  private

  def set_owned_workout
    @workout = current_user.workouts.positioned.find_by_short_id!(params[:workout_id])
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
