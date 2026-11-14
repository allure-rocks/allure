# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Slice 6 product remainder" do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "PWA identity" do
    it "serves a branded manifest" do
      get pwa_manifest_path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/manifest+json")
      expect(response.body).to include("#c5426c")
      expect(response.body).not_to include("red")
      expect(response.body).to include("standalone", "/icon.svg")
    end

    it "links manifest and favicon in the layout" do
      get feed_path

      expect(response.body).to include(%(href="#{pwa_manifest_path}"))
      expect(response.body).to include('href="/icon.svg"')
      expect(response.body).to include('name="theme-color"')
    end
  end

  describe "publishing profile form" do
    it "states that changes are not retroactive" do
      get new_publishing_profile_path

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("publishing_profiles.form.profile_changes")))
    end
  end

  describe "stats locales" do
    it "renders English months and chart locale on demand" do
      running = catalog_sport("running")
      create(:workout, user:, sport: running, distance: 5000, started_at: Time.zone.parse("2026-02-15 08:00:00"))

      get by_time_stats_path(time: "month", locale: "en")

      expect(response.body).to include("February 2026")
      expect(response.body).to include("data-stats-chart-locale-value=\"en\"")
    end
  end
end
