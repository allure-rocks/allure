# frozen_string_literal: true

module Settings
  # The account's heart-rate profile (docs/dev/HEART-RATE.md): maximum,
  # resting value, zone basis and bounds. Saving re-slices the account's
  # histograms under the new zones; clearing it removes every interpretation.
  # Nothing here is ever published.
  class HeartRateController < ApplicationController
    def show
      load_page
    end

    def update
      @user = current_user
      attributes = heart_rate_params
      attributes[:heart_rate_zone_bounds] = Allure::HeartRate::Zones::DEFAULT_BOUNDS.dup if params[:restore_defaults].present?

      if @user.update(attributes)
        HeartRates::RezoneJob.perform_later(@user) if zones_changed?
        redirect_to settings_heart_rate_path, notice: t("settings.heart_rate.update.success")
      else
        load_page
        render :show, status: :unprocessable_content
      end
    end

    def destroy
      @user = current_user
      @user.update!(max_heart_rate: nil, resting_heart_rate: nil, heart_rate_zone_basis: "max",
                    heart_rate_zone_bounds: Allure::HeartRate::Zones::DEFAULT_BOUNDS.dup)
      HeartRates::RezoneJob.perform_later(@user)
      redirect_to settings_heart_rate_path, notice: t("settings.heart_rate.destroy.success")
    end

    private

    def load_page
      @user ||= current_user
      @zones = current_user.heart_rate_zones
      @observed = HeartRates::ObservedMaximum.new(user: current_user).call
      @pending_count = Workouts::UserBackfillJob.pending_scope(current_user, "heart_rate").count
    end

    def zones_changed?
      @user.saved_changes.keys.intersect?(%w[max_heart_rate resting_heart_rate heart_rate_zone_basis heart_rate_zone_bounds])
    end

    def heart_rate_params
      params.require(:user).permit(:max_heart_rate, :resting_heart_rate, :heart_rate_zone_basis, heart_rate_zone_bounds: [])
    end
  end
end
