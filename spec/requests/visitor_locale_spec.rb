# frozen_string_literal: true

require "rails_helper"

# A signed-out visitor reads the language they chose with the switcher, else
# their browser's, else English; an account always reads its own.
RSpec.describe "Visitor locale" do
  def sign_in_title(locale) = CGI.escapeHTML(I18n.t("sessions.new.title", locale:))

  it "follows the browser's Accept-Language" do
    get new_session_path, headers: { "Accept-Language" => "de-DE,de;q=0.9,en;q=0.8" }

    expect(response.body).to include('lang="de"', sign_in_title(:de))
  end

  it "falls back to English when the browser offers no supported language" do
    get new_session_path, headers: { "Accept-Language" => "it-IT,it;q=0.9" }

    expect(response.body).to include('lang="en"', sign_in_title(:en))
  end

  it "falls back to English when the browser names no language" do
    get new_session_path, headers: { "Accept-Language" => "" }

    expect(response.body).to include('lang="en"')
  end

  it "remembers a ?locale= choice over the browser's language" do
    get new_session_path(locale: "nl"), headers: { "Accept-Language" => "de" }
    expect(response.body).to include('lang="nl"')
    expect(response.cookies["allure_locale"]).to eq("nl")

    get new_registration_path, headers: { "Accept-Language" => "de" }
    expect(response.body).to include('lang="nl"')
  end

  it "ignores an unsupported cookie value" do
    cookies[:allure_locale] = "pt"
    get new_session_path, headers: { "Accept-Language" => "es" }

    expect(response.body).to include('lang="es"')
  end

  it "marks signed-out pages as varying by language" do
    get new_session_path

    expect(response.headers["Vary"]).to include("Accept-Language", "Cookie")
  end

  it "offers every language in the switcher, each named in itself" do
    get new_session_path(invitation: "x"), headers: { "Accept-Language" => "fr" }

    I18n.available_locales.each do |locale|
      expect(response.body).to include(%(hreflang="#{locale}"))
      expect(response.body).to include(CGI.escapeHTML(I18n.t("settings.appearance.locales.#{locale}", locale:)))
    end
    expect(response.body).to include("invitation=x&amp;locale=de")
  end

  context "when signed in" do
    let(:user) { create(:user, locale: "es") }

    before { sign_in_as(user) }

    it "uses the account's language over the browser and the cookie" do
      cookies[:allure_locale] = "nl"
      get settings_appearance_path, headers: { "Accept-Language" => "de" }

      expect(response.body).to include('lang="es"')
      expect(response.headers["Vary"].to_s).not_to include("Accept-Language")
    end

    it "does not remember a ?locale= choice" do
      get settings_appearance_path(locale: "de")

      expect(response.body).to include('lang="de"')
      expect(response.cookies).not_to have_key("allure_locale")
    end
  end

  describe "registration" do
    before { allow(Allure::Registration).to receive(:open?).and_return(true) }

    it "gives the new account the language the form was read in" do
      post registration_path, headers: { "Accept-Language" => "nl-NL" }, params: {
        user: { username: "anke", email_address: "anke@example.test", password: "a-long-password-1", password_confirmation: "a-long-password-1" }
      }

      expect(User.find_by!(username: "anke").locale).to eq("nl")
    end
  end
end
