# frozen_string_literal: true

class WorkoutRouteImagesController < ApplicationController
  def show
    workout = current_user&.workouts&.find_by_short_id!(params[:workout_id])
    raise ActiveRecord::RecordNotFound unless workout

    attachment = workout.route_image_variant(params[:theme])
    raise ActiveRecord::RecordNotFound unless attachment

    response.headers["Cache-Control"] = "private, no-store"
    send_data attachment.download,
              filename: attachment.filename.to_s,
              type: "image/png",
              disposition: "inline"
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  # Owner-requested re-render. The job is idempotent and replaces the image
  # under the workout lock, so a double click only queues a second render. A
  # credit row has no track to draw (PLAN_TOGETHER.md §6.6).
  def regenerate
    workout = current_user.workouts.positioned.find_by_short_id!(params[:workout_id])
    Workouts::RenderRouteImageJob.perform_later(workout)
    redirect_to workout_path(workout), notice: t("workouts.route_image.regenerated")
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
