# frozen_string_literal: true

require "rails_helper"

# The About dialog (DESIGN.md §10.23): members only, the instance, the outside
# services actually switched on, the source of the running code.
RSpec.describe "About dialog" do
  let(:user) { create(:user, locale: "en") }

  def dialog
    Nokogiri::HTML(response.body).at_css("#about-modal")
  end

  def with_env(values)
    previous = values.keys.to_h { [ it, ENV[it] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  it "is not rendered for visitors" do
    get new_session_path

    expect(dialog).to be_nil
  end

  it "opens from the account menu and the footer" do
    sign_in_as(user)
    get workouts_path

    page = Nokogiri::HTML(response.body)
    expect(dialog).to be_present
    expect(page.css(%([data-bs-target="#about-modal"])).size).to eq(2)
    expect(page.at_css(%([data-bridge-item="about"]))).to be_present
  end

  it "names the instance, the version and the upstream source by default" do
    sign_in_as(user)
    with_env("ALLURE_SOURCE_URL" => nil) { get workouts_path }

    expect(dialog.text).to include(Allure::Instance.name, Allure::Federation.config.domain, Allure::VERSION)
    expect(dialog.at_css(%(a[href="#{Allure::Instance::DEFAULT_SOURCE_URL}"]))).to be_present
  end

  it "links the source the operator configured" do
    sign_in_as(user)
    with_env("ALLURE_SOURCE_URL" => "https://git.example.org/me/allure") { get workouts_path }

    expect(dialog.at_css(%(a[href="https://git.example.org/me/allure"]))).to be_present
  end

  it "names the operator when one is configured" do
    operator = create(:user)
    sign_in_as(user)
    with_env("INSTANCE_OPERATOR_USERNAME" => operator.username) { get workouts_path }

    expect(dialog.at_css(%(a[href="#{profile_path(operator.username)}"]))).to be_present
  end

  it "lists only the outside services that are switched on" do
    sign_in_as(user)
    with_env("GEOCODING_BASE_URL" => nil, "WEATHER_ENABLED" => nil, "ELEVATION_BASE_URL" => nil) { get workouts_path }

    expect(dialog.text).to include(I18n.t("about.services.maps.label", locale: :en))
    expect(dialog.text).not_to include(I18n.t("about.services.geocoding.label", locale: :en))
    expect(dialog.text).not_to include(I18n.t("about.services.weather.label", locale: :en))

    with_env("GEOCODING_BASE_URL" => "https://nominatim.example.org", "WEATHER_ENABLED" => "true") { get workouts_path }

    expect(dialog.text).to include(I18n.t("about.services.geocoding.label", locale: :en), "nominatim.example.org")
    expect(dialog.text).to include(I18n.t("about.services.weather.label", locale: :en), "open-meteo.com")
    expect(dialog.text).to include("Open-Meteo")
  end
end
