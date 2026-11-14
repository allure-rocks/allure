# frozen_string_literal: true

module Settings
  # Terrain elevation preference (PLAN_ELEVATION.md): when the instance
  # configures an OpenTopoData provider, an account may opt in to sending
  # sampled coordinates of its elevation-less workouts to it.
  class ElevationController < ApplicationController
    def show
      @user = current_user
    end

    def update
      @user = current_user
      if @user.update(elevation_params)
        # Consent makes the account's private and followers-only courses
        # eligible for the terrain profile.
        if @user.saved_change_to_elevation_enrichment_enabled?(to: true) && Allure::Elevation::Config.configured?
          Segments::BackfillTerrainElevationJob.perform_later(user_id: @user.id)
        end
        redirect_to settings_elevation_path, notice: t("settings.elevation.update.success")
      else
        render :show, status: :unprocessable_content
      end
    end

    private

    def elevation_params
      params.require(:user).permit(:elevation_enrichment_enabled)
    end
  end
end
