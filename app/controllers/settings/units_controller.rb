# frozen_string_literal: true

module Settings
  # Measurement and calendar preferences: unit system, time zone, week start.
  class UnitsController < ApplicationController
    def show
      @user = current_user
    end

    def update
      @user = current_user
      if @user.update(units_params)
        redirect_to settings_units_path, notice: t("settings.units.update.success")
      else
        render :show, status: :unprocessable_content
      end
    end

    private

    def units_params
      params.require(:user).permit(:unit_system, :time_zone, :week_start)
    end
  end
end
