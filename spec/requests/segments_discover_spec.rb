# frozen_string_literal: true

require "rails_helper"

# The Découvrir page (PLAN_SEGMENTS.md §8.4): the map alone, showing every
# course the viewer may see — the readable shared ones and their own, private
# ones included — with no filter and no cards.
RSpec.describe "Discover page" do
  let(:viewer) { create(:user) }
  let(:owner) { create(:user) }
  let(:sport) { create(:sport) }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "allure-test-password" }
  end

  before { sign_in(viewer) }

  it "renders the map alone with its endpoint and opening position" do
    create(:segment, user: owner, sport:, visibility: "public", name: "Col partagé")
    create(:workout, user: viewer)

    get segments_path(kind: "discover")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      'data-controller="segments-map"',
      segments_discover_map_path,
      "data-segments-map-center-value=",
      I18n.t("segments.index.discover_title")
    )
    expect(response.body).not_to include("allure-segment-card", "allure-filter-bar", "nav-tabs")
  end

  it "offers the way back to the list" do
    create(:segment, user: owner, sport:, visibility: "public", name: "Col partagé")

    get segments_path(kind: "discover")

    link = Nokogiri::HTML(response.body).css(".page-header a, a.btn").find { |node| node.text.strip == I18n.t("segments.index.kinds.list") }
    expect(link&.[]("href")).to eq(segments_path)
  end

  it "wires the unit system and the account's basemap into the map" do
    viewer.update!(unit_system: "imperial", theme: "light", route_image_theme: "dark")
    create(:segment, user: owner, sport:, visibility: "public", name: "Col partagé")

    get segments_path(kind: "discover")

    expect(response.body).to include(
      'data-segments-map-unit-system-value="imperial"',
      'data-segments-map-basemap-theme-value="dark"'
    )
    canvas = Nokogiri::HTML(response.body).at_css('[data-segments-map-target="canvas"]')
    expect(canvas["data-bs-theme"]).to eq("dark")
  end

  it "points at the people directory when nothing is visible yet" do
    get segments_path(kind: "discover")

    expect(response.body).to include(
      I18n.t("segments.index.discover_empty_title"),
      I18n.t("segments.index.discover_empty_action"),
      people_path
    )
    expect(response.body).not_to include('data-controller="segments-map"')
  end

  it "keeps the map when the viewer only has their own private courses" do
    create(:segment, user: viewer, sport:, visibility: "private", name: "Ma boucle privée")

    get segments_path(kind: "discover")

    expect(response.body).not_to include(I18n.t("segments.index.discover_empty_title"))
    expect(response.body).to include('data-controller="segments-map"')
  end

  it "offers the discover action from the kind page" do
    get segments_path

    expect(response.body).to include(
      segments_path(kind: "discover"),
      I18n.t("segments.index.kinds.discover")
    )
  end
end
