# frozen_string_literal: true

module Settings
  # Account appearance: theme, locale, and the track-display smoothing
  # preference. The topbar theme toggle and the map options toggle PATCH
  # update directly with a single JSON key; the page edits everything through
  # the account form.
  class AppearanceController < ApplicationController
    def show
      @user = current_user
    end

    def update
      unless params.key?(:user)
        update_single_preference
        return
      end

      @user = current_user
      if @user.update(appearance_params)
        redirect_to settings_appearance_path, notice: t("settings.appearance.update.success")
      else
        render :show, status: :unprocessable_content
      end
    end

    private

    # One-key JSON PATCHes (theme, smooth_tracks) so the header and map
    # controls persist without a full form round-trip.
    def update_single_preference
      if params.key?(:smooth_tracks)
        smooth_tracks = params[:smooth_tracks]
        unless [ true, false ].include?(smooth_tracks)
          render json: { error: "smooth_tracks" }, status: :unprocessable_content
          return
        end

        current_user.update!(smooth_tracks:)
        head :no_content
        return
      end

      theme = params[:theme].to_s
      unless User::THEMES.include?(theme)
        render json: { error: "theme" }, status: :unprocessable_content
        return
      end

      current_user.update!(theme:)
      head :no_content
    end

    def appearance_params
      params.require(:user).permit(:theme, :locale, :smooth_tracks, :track_smoothing_level, :route_image_theme)
    end
  end
end
