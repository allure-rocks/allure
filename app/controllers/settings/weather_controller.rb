# frozen_string_literal: true

module Settings
  # Weather consent (PLAN_WEATHER.md §1, §7): off for every account until it
  # opts in. Withdrawing consent stops every request at once and keeps the
  # weather already stored until the owner deletes it here.
  class WeatherController < ApplicationController
    before_action :require_feature

    def show
      @user = current_user
      @stored_count = stored_scope.count
    end

    def update
      @user = current_user
      enabling = ActiveModel::Type::Boolean.new.cast(weather_params[:weather_enrichment_enabled])
      if @user.update(weather_params)
        notice = enabling ? "settings.weather.update.enabled" : "settings.weather.update.disabled"
        redirect_to settings_weather_path, notice: t(notice)
      else
        @stored_count = stored_scope.count
        render :show, status: :unprocessable_content
      end
    end

    def destroy
      count = 0
      WorkoutWeather.transaction do
        count = stored_scope.delete_all
        current_user.workouts.recordings.where.not(weather_start: nil)
          .update_all(weather_start: nil, weather_end: nil, updated_at: Time.current)
      end
      redirect_to settings_weather_path, notice: t("settings.weather.destroy.success", count:)
    end

    private

    def stored_scope
      WorkoutWeather.where(workout_id: current_user.workouts.select(:id))
    end

    def weather_params
      params.require(:user).permit(:weather_enrichment_enabled)
    end

    def require_feature
      raise ActiveRecord::RecordNotFound unless Allure::Weather::Config.enabled?
    end
  end
end
