# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings elevation" do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  it "renders the opt-in with the mandatory privacy copy" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
      get settings_elevation_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.elevation.enrichment_label")))
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("settings.elevation.privacy", provider: "https://elevation.test"))
      )
      expect(response.body).to include("https://elevation.test")
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.elevation.segments_privacy")))
    end
  end

  it "enables and disables the preference" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
      patch settings_elevation_path, params: { user: { elevation_enrichment_enabled: "1" } }

      expect(response).to redirect_to(settings_elevation_path)
      expect(user.reload.elevation_enrichment_enabled).to be(true)
      # Consent makes the account's private courses eligible for the terrain.
      expect(Segments::BackfillTerrainElevationJob).to have_been_enqueued.with(user_id: user.id)

      patch settings_elevation_path, params: { user: { elevation_enrichment_enabled: "0" } }

      expect(user.reload.elevation_enrichment_enabled).to be(false)
    end
  end

  it "explains an unconfigured instance without exposing the toggle" do
    with_env("ELEVATION_BASE_URL" => nil) do
      get settings_elevation_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.elevation.not_configured")))
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("settings.elevation.enrichment_label")))
    end
  end

  it "links the page from the settings shell only when configured" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
      get settings_profile_path

      expect(response.body).to include(settings_elevation_path)
    end

    with_env("ELEVATION_BASE_URL" => nil) do
      get settings_profile_path

      expect(response.body).not_to include(settings_elevation_path)
    end
  end

  def with_env(values)
    previous = values.to_h { |key, _value| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
