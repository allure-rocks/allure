# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Slice 6 settings remainder" do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "appearance" do
    it "renders theme and locale controls" do
      get settings_appearance_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("settings.appearance.theme_title"))
      expect(response.body).to include(I18n.t("settings.appearance.locales.fr"))
    end

    it "updates theme and locale together" do
      patch settings_appearance_path, params: { user: { theme: "dark", locale: "en" } }

      expect(response).to redirect_to(settings_appearance_path)
      expect(user.reload.theme).to eq("dark")
      expect(user.locale).to eq("en")
    end

    it "rejects an unknown locale" do
      patch settings_appearance_path, params: { user: { locale: "pt" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.locale).to eq("fr")
    end

    it "keeps the JSON theme toggle working" do
      patch settings_appearance_path, params: { theme: "dark" }

      expect(response).to have_http_status(:no_content)
      expect(user.reload.theme).to eq("dark")
    end

    it "renders and updates the track smoothing preference" do
      get settings_appearance_path
      expect(response.body).to include(I18n.t("settings.appearance.smooth_tracks"))
      expect(response.body).to include(I18n.t("settings.appearance.smoothing_levels.medium"))

      patch settings_appearance_path, params: { user: { smooth_tracks: "1", track_smoothing_level: "strong" } }

      expect(response).to redirect_to(settings_appearance_path)
      expect(user.reload.smooth_tracks).to be(true)
      expect(user.track_smoothing_level).to eq("strong")
    end

    it "toggles the smoothing preference through the JSON endpoint" do
      patch settings_appearance_path, params: { smooth_tracks: true }, as: :json

      expect(response).to have_http_status(:no_content)
      expect(user.reload.smooth_tracks).to be(true)

      patch settings_appearance_path, params: { smooth_tracks: "yes" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.smooth_tracks).to be(true)
    end

    it "renders and updates the route image theme preference" do
      get settings_appearance_path
      page = Nokogiri::HTML(response.body).text
      expect(page).to include(I18n.t("settings.appearance.images_title"))
      expect(page).to include(I18n.t("settings.appearance.image_themes.auto"))

      patch settings_appearance_path, params: { user: { route_image_theme: "dark" } }

      expect(response).to redirect_to(settings_appearance_path)
      expect(user.reload.route_image_theme).to eq("dark")
    end

    it "rejects an unknown route image theme" do
      patch settings_appearance_path, params: { user: { route_image_theme: "sepia" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.route_image_theme).to eq("auto")
    end
  end

  describe "units" do
    it "renders system, zone, and week-start controls" do
      get settings_units_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.units.system_title")))
      expect(response.body).to include(I18n.t("settings.units.time_zone"))
      expect(response.body).to include(I18n.t("settings.units.week_start_hint"))
    end

    it "offers IANA identifiers and selects the stored zone" do
      user.update!(time_zone: "Europe/Brussels")

      get settings_units_path

      expect(response.body).to include('<option selected="selected" value="Europe/Brussels">(GMT+01:00) Brussels</option>')
      expect(response.body).not_to include('value="Brussels"')
    end

    it "saves a zone chosen from the rendered options" do
      get settings_units_path
      value = response.body[/<option value="([^"]+)">\([^)]+\) Brussels</, 1]

      patch settings_units_path, params: { user: { time_zone: value } }

      expect(response).to redirect_to(settings_units_path)
      expect(user.reload.time_zone).to eq("Europe/Brussels")
    end

    it "updates all three preferences" do
      patch settings_units_path,
            params: { user: { unit_system: "imperial", time_zone: "America/New_York", week_start: "sunday" } }

      expect(response).to redirect_to(settings_units_path)
      expect(user.reload.unit_system).to eq("imperial")
      expect(user.time_zone).to eq("America/New_York")
      expect(user.week_start).to eq("sunday")
    end

    it "rejects an unknown unit system" do
      patch settings_units_path, params: { user: { unit_system: "furlongs" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.unit_system).to eq("metric")
    end
  end

  describe "shell" do
    it "renders the universal /settings hub with every group" do
      get settings_path

      expect(response).to have_http_status(:ok)

      page = response.parsed_body
      expect(page.at_css("h1.page-title").text).to eq(I18n.t("settings.hub.title"))

      hub = page.at_css(".settings-hub")
      expect(hub).to be_present
      expect(hub.text).to include(
        I18n.t("settings.nav.groups.account"),
        I18n.t("settings.nav.groups.publishing"),
        I18n.t("settings.nav.groups.system")
      )
      expect(hub.css("a.list-group-item").map { |link| link["href"] }).to include(
        settings_profile_path, settings_appearance_path, settings_notifications_path,
        publishing_profiles_path, privacy_zones_path, settings_security_path, settings_account_path
      )
    end

    it "links back to the hub from a sub-page on phones" do
      get settings_appearance_path

      back = response.parsed_body.at_css("a.settings-back")
      expect(back).to be_present
      expect(back["href"]).to eq(settings_path)
      expect(back.at_xpath("parent::div")["class"]).to include("d-md-none")
    end

    it "marks the current section and names the navigation groups" do
      get settings_appearance_path

      page = response.parsed_body

      expect(page.at_css("h1.page-title").text).to eq(I18n.t("settings.hub.title"))

      nav = page.at_css(".settings-nav-menu")
      expect(nav).to be_present
      expect(nav.text).to include(
        I18n.t("settings.nav.groups.account"),
        I18n.t("settings.nav.groups.publishing"),
        I18n.t("settings.nav.groups.system")
      )

      active = nav.at_css("a.list-group-item.active")
      expect(active["href"]).to eq(settings_appearance_path)
      expect(active["aria-current"]).to eq("page")

      expect(page.at_css(".col-md-9 h2").text).to eq(I18n.t("settings.appearance.title"))
    end

    it "keeps header actions inside the shell header" do
      get publishing_profiles_path

      actions = response.parsed_body.at_css(".page-header .col-auto.ms-auto")
      expect(actions.at_css("a")["href"]).to eq(new_publishing_profile_path)
    end

    it "links every settings page from the shell, and settings from the account menu" do
      get settings_profile_path

      expect(response.body).to include(
        %(href="#{settings_appearance_path}"),
        %(href="#{settings_units_path}"),
        %(href="#{settings_sports_path}")
      )

      get feed_path

      expect(response.body).to include(%(href="#{settings_path}"))
    end

    it "redirects anonymous visitors" do
      delete session_path

      get settings_appearance_path
      expect(response).to redirect_to(new_session_path)

      get settings_units_path
      expect(response).to redirect_to(new_session_path)

      get settings_security_path
      expect(response).to redirect_to(new_session_path)
    end
  end
end
