# frozen_string_literal: true

require "rails_helper"

# PLAN_HEART_RATE.md slice 1: the profile page, the « Zones » analysis tab,
# the owner's rebuild, and the API fields.
RSpec.describe "Heart rate", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  def recording(owner = user, max_heart_rate: 176, contested: [])
    workout = create(:workout, user: owner, title: "Col du Lautaret", max_heart_rate:, contested_metrics: contested)
    create(:track_segment, workout:, points: (0..60).map do |index|
      { "t" => index * 10, "d" => index * 40.0, "lat" => 45.07 + (index * 0.0001), "lon" => 6.40,
        "hr" => index < 30 ? 120 : 176 }
    end)
    HeartRates::Rebuild.new(workout:).call
    workout
  end

  # The proposal's own value, never a whole-body digit match: the generated
  # avatar palette contains #b3205f, so the page may legitimately show "205".
  def proposed_max_heart_rate
    response.parsed_body.at_css("input[type=hidden][name='user[max_heart_rate]']")&.[]("value")
  end

  describe "settings page" do
    before { sign_in_as(user) }

    it "proposes the observed maximum, skipping contested values, and is linked from the shell" do
      recording(max_heart_rate: 176)
      recording(max_heart_rate: 215, contested: %w[max_heart_rate])

      get settings_heart_rate_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("settings.heart_rate.observed.title"))
      expect(proposed_max_heart_rate).to eq("176")
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.heart_rate.privacy")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.heart_rate.empty")))
    end

    it "proposes the highest heart rate held ten seconds, never a single spike" do
      # This seed's generated avatar background is #b3205f: the page contains
      # "205" even though the proposal must not.
      user.update!(avatar_seed: 19)
      workout = create(:workout, user:, title: "Sortie au pic", max_heart_rate: 205)
      create(:track_segment, workout:, points: (0..120).map do |index|
        { "t" => index, "d" => index * 8.0, "lat" => 45.07, "lon" => 6.40, "hr" => index == 60 ? 205 : 150 + (index % 3) }
      end)
      HeartRates::Rebuild.new(workout:).call

      get settings_heart_rate_path

      expect(proposed_max_heart_rate).to eq("152")
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.heart_rate.observed.floor")))
    end

    it "renders the zone table for a live preview, with the load floor" do
      user.update!(max_heart_rate: 190)

      get settings_heart_rate_path

      expect(response.body).to include('data-controller="heart-rate-zones-preview"')
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("heart_rate.zones.descriptions.endurance")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("heart_rate.load_floor.max", bpm: 95, percent: 50)))
    end

    it "saves the profile, shows the zones and re-slices the account's histograms" do
      patch settings_heart_rate_path, params: { user: { max_heart_rate: "190", resting_heart_rate: "",
                                                        heart_rate_zone_basis: "max",
                                                        heart_rate_zone_bounds: %w[55 72 82 92] } }

      expect(response).to redirect_to(settings_heart_rate_path)
      expect(user.reload).to have_attributes(max_heart_rate: 190, heart_rate_zone_bounds: [ 55, 72, 82, 92 ])
      expect(HeartRates::RezoneJob).to have_been_enqueued.with(user)

      get settings_heart_rate_path
      expect(response.body).to include("137–155")
    end

    it "restores the default thresholds" do
      user.update!(max_heart_rate: 190, heart_rate_zone_bounds: [ 55, 72, 82, 92 ])

      patch settings_heart_rate_path, params: { restore_defaults: "1", user: { max_heart_rate: "190" } }

      expect(user.reload.heart_rate_zone_bounds).to eq([ 60, 70, 80, 90 ])
    end

    it "explains invalid thresholds" do
      patch settings_heart_rate_path, params: { user: { max_heart_rate: "190", heart_rate_zone_bounds: %w[60 50 80 90] } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(ERB::Util.html_escape(
        I18n.t("activerecord.errors.models.user.attributes.heart_rate_zone_bounds.invalid_bounds")
      ))
    end

    it "clears the profile" do
      user.update!(max_heart_rate: 190, resting_heart_rate: 50)

      delete settings_heart_rate_path

      expect(user.reload).to have_attributes(max_heart_rate: nil, resting_heart_rate: nil)
      expect(HeartRates::RezoneJob).to have_been_enqueued.with(user)
    end

    it "rebuilds the account's histograms from the data page" do
      create(:workout, user:)

      post settings_data_heart_rate_path

      expect(response).to redirect_to(settings_data_path)
      expect(Workouts::UserBackfillJob).to have_been_enqueued.with(user.id, "heart_rate")
    end
  end

  describe "workout page" do
    it "shows the zones tab to the owner with a profile" do
      user.update!(max_heart_rate: 190)
      workout = recording
      sign_in_as(user)

      get workout_path(workout)

      expect(response.body).to include("id=\"workout-laps-tab-heart_rate\"")
      expect(response.body).to include(I18n.t("heart_rate.zones.names.endurance"))
      expect(response.body).to include("allure-zone-bar")
      # Each zone row previews where it was ridden on the profile and the map.
      expect(response.body).to include("data-analysis-ranges=\"[[0.0,1200.0]]\"")
      expect(response.body).to include("data-analysis-source=\"heart_rate_zone\"")
    end

    it "states the basis and the session's load" do
      user.update!(max_heart_rate: 190)
      workout = recording
      sign_in_as(user)

      get workout_path(workout)

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("heart_rate.zones.basis.max", max: 190)))
      expect(response.body).to include(I18n.t("heart_rate.zones.load", load: "35"))
    end

    it "says why a recording with too little heart rate has no zones" do
      user.update!(max_heart_rate: 190)
      workout = create(:workout, user:)
      create(:track_segment, workout:, points: (0..100).map do |index|
        { "t" => index * 10, "d" => index * 40.0, "lat" => 45.07, "lon" => 6.40 }
          .tap { it["hr"] = 140 + (index % 4) if index < 30 }
      end)
      HeartRates::Rebuild.new(workout:).call
      sign_in_as(user)

      get workout_path(workout)

      expect(response.body).to include(I18n.t("workouts.show.laps.tabs.heart_rate"))
      percent = ->(value) { ActiveSupport::NumberHelper.number_to_percentage(value, precision: 0) }
      expect(response.body).to include(ERB::Util.html_escape(
        I18n.t("heart_rate.zones.unusable.partial", share: percent.call(30), minimum: percent.call(50))
      ))
      expect(response.body).not_to include("allure-zone-bar")
    end

    it "shows no tab without a profile" do
      workout = recording
      sign_in_as(user)

      get workout_path(workout)

      expect(response.body).not_to include("workout-laps-tab-heart_rate")
    end
  end

  describe "hub and statistics (slice 2)" do
    before { sign_in_as(user) }

    it "hides the training load until a recording carries heart rate" do
      get me_path

      expect(response.body).not_to include("training-load-chart")
      expect(response.body).not_to include(settings_heart_rate_path)
    end

    it "invites to set a profile, then shows fitness, fatigue and form" do
      # A Wednesday ten days after the recording: the current week is
      # unfinished and the history is still warming up.
      travel_to Time.zone.parse("2026-09-02 12:00")
      recording
      get me_path
      expect(response.body).to include(I18n.t("me.training_load.empty_action"))

      user.update!(max_heart_rate: 190)
      get me_path

      expect(response.body).to include(I18n.t("me.training_load.fitness"))
      expect(response.body).to include("training-load-chart")
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("me.training_load.table_caption")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("me.training_load.how_title")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("me.training_load.warming_up")))
      expect(response.body).to include(I18n.t("me.training_load.week_states.current"))
    end

    it "shows the zone distribution per week with its table" do
      user.update!(max_heart_rate: 190)
      workout = recording
      workout.update!(started_at: 2.days.ago)

      get heart_rate_stats_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("zone-distribution-chart")
      expect(response.body).to include(I18n.t("stats.heart_rate.table_caption"))

      expect(response.body).to include(I18n.t("stats.heart_rate.split.title"))

      get heart_rate_stats_path(time: "month", scale: "share")
      expect(response.body).to include(I18n.t("stats.heart_rate.granularities.month"))
      expect(response.body).to include(I18n.t("stats.heart_rate.chart_titles.share"))
      expect(response.body).to include("&quot;scale&quot;:&quot;share&quot;")
    end

    it "filters by sport and period with the hub's controls, keeping the other choices" do
      user.update!(max_heart_rate: 190)
      workout = recording
      workout.update!(started_at: 2.days.ago)
      sport = workout.sport

      get heart_rate_stats_path(scale: "share", sport_id: sport.id)
      page = Nokogiri::HTML(response.body)

      pills = page.at_css(".hub-toolbar .allure-sport-filter")
      expect(pills.at_css("input#heart_rate_sport_#{sport.id}[checked]")).to be_present
      expect(pills.css(".allure-sport-filter__count").map(&:text)).to eq(%w[1 1])
      expect(page.at_css("form.hub-toolbar__sports input[name=scale]")["value"]).to eq("share")

      period_links = page.css(".hub-period-switch a.nav-link")
      expect(period_links.find { it["aria-current"] == "true" }.text).to eq(I18n.t("stats.heart_rate.granularities.week"))
      expect(period_links.last["href"]).to eq(heart_rate_stats_path(time: "month", scale: "share", sport_id: sport.id))

      expect(page.at_css("select#heart_rate_sport_select option[selected]")["value"]).to eq(sport.id.to_s)
      expect(page.at_css("select#heart_rate_granularity_select option[selected]")["value"]).to eq("week")

      scale_links = page.css(".card-actions nav a.nav-link")
      expect(scale_links.find { it["aria-current"] == "true" }.text).to eq(I18n.t("stats.heart_rate.scales.share"))
      expect(page.at_css("select#heart_rate_scale_select option[selected]")["value"]).to eq("share")
    end

    it "lists each period on phones with its total, zone bar and five values" do
      user.update!(max_heart_rate: 190)
      workout = recording
      workout.update!(started_at: 2.days.ago)

      get heart_rate_stats_path
      page = Nokogiri::HTML(response.body)

      items = page.css("ul.allure-card-list li")
      expect(items.size).to eq(page.css("table tbody tr").size)
      expect(items.first.css(".allure-zone-values dd").map { it.text.strip }).to eq([ "—", "5:00", "—", "—", "5:00" ])
      expect(items.first.css(".allure-zone-bar .progress-bar").size).to eq(2)
    end

    it "explains the missing profile on the statistics page" do
      get heart_rate_stats_path

      expect(response.body).to include(I18n.t("stats.heart_rate.no_profile_title"))
    end
  end

  describe "REST API" do
    it "serves the profile and the workout's zones to the token's owner" do
      user.update!(max_heart_rate: 190)
      workout = recording

      get "/api/rest/v1/me", headers: api_headers_for(user)
      expect(response.parsed_body["heart_rate_profile"]).to include("max" => 190, "thresholds_bpm" => [ 114, 133, 152, 171 ])
      expect_api_contract

      get "/api/rest/v1/workouts/#{workout.to_param}", headers: api_headers_for(user)
      heart_rate = response.parsed_body["heart_rate"]
      expect(heart_rate).to include("sampled_seconds" => 600, "covered_seconds" => 600, "coverage" => 1.0,
                                    "frozen_seconds" => 0, "load" => 35.0, "load_floor_bpm" => 95)
      expect(heart_rate["zones"].pluck("seconds")).to eq([ 0, 300, 0, 0, 300 ])
      expect_api_contract
    end

    it "answers null without a usable histogram or a profile" do
      workout = create(:workout, user:)

      get "/api/rest/v1/me", headers: api_headers_for(user)
      expect(response.parsed_body["heart_rate_profile"]).to be_nil
      expect_api_contract

      get "/api/rest/v1/workouts/#{workout.to_param}", headers: api_headers_for(user)
      expect(response.parsed_body["heart_rate"]).to be_nil
      expect_api_contract
    end
  end
end
