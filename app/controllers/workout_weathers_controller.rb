# frozen_string_literal: true

# Owner-requested weather refresh (PLAN_WEATHER.md §7): a missing or failed
# weather is asked again. The job is paced and idempotent; an unchanged plan
# converges offline from the kept responses.
class WorkoutWeathersController < ApplicationController
  def create
    workout = current_user.workouts.positioned.find_by_short_id!(params[:workout_id])
    if Workouts::WeatherEligibility.eligible?(workout) && Workouts::WeatherRefresh.new(workout:).call
      redirect_to workout_path(workout, anchor: "section-weather"), notice: t("workouts.weather.refreshed")
    else
      redirect_to workout_path(workout), alert: t("workouts.weather.refresh_unavailable")
    end
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
