# frozen_string_literal: true

module Settings
  # Per-account sport defaults (PLAN_M1.md §3.4): the variant used when an
  # import detects a generic sport (`cycling`, `running`, `walking`). Nil keeps
  # the detected generic; an explicit detection is never overridden.
  class SportsController < ApplicationController
    def show
      @user = current_user
    end

    def update
      @user = current_user
      if @user.update(sport_default_params)
        redirect_to settings_sports_path, notice: t("settings.sports.update.success")
      else
        render :show, status: :unprocessable_content
      end
    end

    private

    def sport_default_params
      params.require(:user).permit(*User::SPORT_DEFAULT_KEYS.values.map { :"#{it}_id" })
    end
  end
end
