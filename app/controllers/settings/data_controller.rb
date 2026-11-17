# frozen_string_literal: true

module Settings
  # Owner-scoped derived-data maintenance (docs/dev/DERIVATIONS.md). The page
  # shows how many of the account's workouts are concerned by each rebuild and
  # enqueues one throttled cursor sweep per action; the counters refresh
  # through the shared live frame. Nothing here reaches another account's
  # workouts, and a sweep only rebuilds to the current code and catalogue.
  class DataController < ApplicationController
    before_action :set_no_store

    def show
      @counts = Workouts::UserBackfillJob.counts(current_user)
      @elevation_available = elevation_available?
      @weather_available = weather_available?
      return if request.headers["Turbo-Frame"].blank?

      render partial: "settings/data/live",
             locals: { counts: @counts, elevation_available: @elevation_available, weather_available: @weather_available },
             layout: false
    end

    def rebuild = enqueue("rebuild")
    def route_images = enqueue("route_images")
    def segment_images = enqueue("segment_images")
    def places = enqueue("places")
    def elevation = enqueue("elevation")
    def weather = enqueue("weather")
    def loops = enqueue("loops")
    def heart_rate = enqueue("heart_rate")
    def route_suggestions = enqueue("route_suggestions")

    private

    def enqueue(kind)
      if kind == "elevation" && !elevation_available?
        return redirect_to settings_data_path, notice: t("settings.data.flash.elevation_current")
      end
      if kind == "weather" && !weather_available?
        return redirect_to settings_data_path, notice: t("settings.data.flash.weather_current")
      end

      count = Workouts::UserBackfillJob.pending_scope(current_user, kind).count
      if count.positive?
        Workouts::UserBackfillJob.perform_later(current_user.id, kind)
        redirect_to settings_data_path, notice: t("settings.data.flash.#{kind}", count:)
      else
        redirect_to settings_data_path, notice: t("settings.data.flash.#{kind}_current")
      end
    end

    def elevation_available?
      Allure::Elevation::Config.configured? && current_user.elevation_enrichment_enabled?
    end

    def weather_available?
      Allure::Weather::Config.enabled? && current_user.weather_enrichment_enabled?
    end

    def set_no_store
      response.set_header("Cache-Control", "no-store")
    end
  end
end
