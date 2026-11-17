# frozen_string_literal: true

require "rails_helper"

# Weather consent, the owner's card and refresh, and the data page sweep
# (docs/dev/WEATHER.md).
RSpec.describe "Weather", :weather do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "consent" do
    it "is off by default and states what leaves the instance" do
      get settings_weather_path

      expect(response).to have_http_status(:ok)
      expect(user.weather_enrichment_enabled).to be(false)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.weather.privacy")))
    end

    it "turns on and off, keeping stored weather until it is deleted" do
      patch settings_weather_path, params: { user: { weather_enrichment_enabled: "1" } }
      expect(response).to redirect_to(settings_weather_path)
      expect(user.reload.weather_enrichment_enabled).to be(true)

      workout = weather_workout(user:)
      create(:workout_weather, workout:)
      workout.update_columns(weather_start: { "temp" => 11.2 })

      patch settings_weather_path, params: { user: { weather_enrichment_enabled: "0" } }
      expect(user.reload.weather_enrichment_enabled).to be(false)
      expect(workout.reload.weather).to be_present

      delete settings_weather_path
      expect(workout.reload.weather).to be_nil
      expect(workout.weather_start).to be_nil
    end

    it "is not found while the instance does not offer weather" do
      ENV.delete("WEATHER_ENABLED")

      get settings_weather_path

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the owner's workout page" do
    let(:workout) { weather_workout(user:) }

    it "shows nothing without consent" do
      get workout_path(workout)

      expect(response.body).not_to include('id="section-weather"')
    end

    it "offers to fetch, then shows the stored summary and the hourly tab" do
      user.update!(weather_enrichment_enabled: true)

      get workout_path(workout)
      expect(response.body).to include(I18n.t("weather.card.fetch"))

      create(:workout_weather, workout:)
      get workout_path(workout)

      expect(response.body).to include(I18n.t("weather.conditions.partly_cloudy"))
      expect(response.body).to include("Open-Meteo.com")
      expect(response.body).to include(I18n.t("workouts.show.laps.tabs.weather"))
      expect(response.body).to include("#{I18n.t("weather.exposure.head", share: "")}42")
      expect(response.body).to include("allure-weather-badge", "13 °C")
      expect(response.body).to include("&quot;kind&quot;:&quot;weather&quot;")
      expect(response.body.index('id="section-laps"')).to be < response.body.index('id="section-weather"')
    end

    it "converts temperatures for an imperial reader" do
      user.update!(weather_enrichment_enabled: true, unit_system: "imperial")
      create(:workout_weather, workout:)

      get workout_path(workout)

      expect(response.body).to include("52–60 °F")
    end

    it "queues a refresh for the owner only" do
      user.update!(weather_enrichment_enabled: true)

      expect {
        post workout_weather_path(workout)
      }.to have_enqueued_job(Workouts::EnrichWeatherJob).with(workout)
      expect(workout.reload.weather).to be_pending

      sign_in_as(create(:user, weather_enrichment_enabled: true))
      post workout_weather_path(workout)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the data page" do
    it "schedules the account's missing weather" do
      user.update!(weather_enrichment_enabled: true)
      weather_workout(user:)

      get settings_data_path
      expect(response.body).to include(I18n.t("settings.data.weather.action"))

      post settings_data_weather_path

      expect(response).to redirect_to(settings_data_path)
      expect(Workouts::UserBackfillJob).to have_been_enqueued.with(user.id, "weather")
    end
  end
end
