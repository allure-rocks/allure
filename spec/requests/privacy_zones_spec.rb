# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Privacy zones" do
  let(:owner) { create(:user) }

  before { sign_in_as(owner) }

  # DESIGN.md §19.7: the panel is persistent on the index and the editor.
  it "states what a zone does on the index and the editor" do
    zone = create(:privacy_zone, user: owner)
    panel = CGI.escapeHTML(I18n.t("privacy_zones.panel", locale: owner.locale))

    [ privacy_zones_path, new_privacy_zone_path, edit_privacy_zone_path(zone) ].each do |path|
      get path

      expect(response.body).to include(panel)
      expect(response.body).to include(help_topic_path("privacy-zones"))
    end
  end

  it "lists only the signed-in user's zones" do
    zone = create(:privacy_zone, user: owner, name: "Owner zone")
    create(:privacy_zone, name: "Other zone")

    get privacy_zones_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(zone.name)
    expect(response.body).not_to include("Other zone")
  end

  it "lists the zones as a table like the publishing profiles" do
    create(:privacy_zone, user: owner, name: "Maison", radius_meters: 250)
    create(:privacy_zone, user: owner, name: "Bureau", active: false)

    get privacy_zones_path

    page = Nokogiri::HTML(response.body)
    rows = page.css("table.card-table tbody tr")
    expect(rows.map { it.at_css("a.fw-medium").text.strip }).to eq(%w[Maison Bureau])
    expect(rows.first.text).to include("250 m")
    expect(rows.last["class"]).to include("text-secondary")
    expect(rows.last.text).to include("Inactive")
    expect(page.at_css('a[aria-label="Modifier : Maison"]')).to be_present
    expect(page.at_css('button[aria-label="Supprimer : Bureau"]')).to be_present
  end

  it "offers the place search only when geocoding is configured" do
    allow(Allure::Toponyms::Config).to receive(:base_url).and_return(nil)
    get new_privacy_zone_path
    expect(response.body).not_to include('data-zone-picker-target="search"')

    allow(Allure::Toponyms::Config).to receive(:base_url).and_return("https://geocoding.test")
    get new_privacy_zone_path
    expect(response.body).to include('data-zone-picker-target="search"', ERB::Util.html_escape(I18n.t("privacy_zones.form.search.hint")))
  end

  describe "place search" do
    let(:search_url) { "https://geocoding.test/search" }

    before { allow(Allure::Toponyms::Config).to receive(:base_url).and_return("https://geocoding.test") }

    it "answers the provider's places through the instance" do
      stub_request(:get, search_url)
        .with(query: hash_including("q" => "Place Grenette Grenoble", "accept-language" => "fr"))
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: [
          { "display_name" => "Place Grenette, Grenoble", "lat" => "45.1907", "lon" => "5.7274" }
        ].to_json)

      get search_privacy_zones_path, params: { privacy_zone_query: "  Place Grenette   Grenoble " }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.parsed_body).to eq(
        "results" => [ { "label" => "Place Grenette, Grenoble", "latitude" => 45.1907, "longitude" => 5.7274 } ]
      )
    end

    it "refuses a query that is too short without calling the provider" do
      get search_privacy_zones_path, params: { privacy_zone_query: "ab" }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(a_request(:get, /geocoding\.test/)).not_to have_been_made
    end

    it "answers 503 when the provider fails" do
      stub_request(:get, /geocoding\.test/).to_return(status: 500)

      get search_privacy_zones_path, params: { privacy_zone_query: "Grenoble" }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:service_unavailable)
    end

    it "answers 404 while geocoding is not configured" do
      allow(Allure::Toponyms::Config).to receive(:base_url).and_return(nil)

      get search_privacy_zones_path, params: { privacy_zone_query: "Grenoble" }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:not_found)
    end

    it "slows down a flood of searches" do
      # The test cache is a null store; this answers as a store that counted
      # past the limit.
      allow(PrivacyZonesController.cache_store).to receive(:increment).and_return(31)

      get search_privacy_zones_path, params: { privacy_zone_query: "Grenoble" }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "keeps the query out of the logs" do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

      expect(filter.filter("privacy_zone_query" => "12 rue de chez moi")).to eq("privacy_zone_query" => "[FILTERED]")
    end
  end

  it "creates a zone from longitude, latitude, and radius" do
    expect do
      post privacy_zones_path, params: {
        privacy_zone: { name: "Office", latitude: "45.08", longitude: "6.42", radius_meters: "250" }
      }
    end.to change(PrivacyZone, :count).by(1)

    zone = owner.privacy_zones.order(:id).last
    expect(response).to redirect_to(privacy_zones_path)
    expect([ zone.longitude, zone.latitude, zone.radius_meters ]).to eq([ 6.42, 45.08, 250 ])
    expect(zone).to be_active
  end

  it "hides activation when creating and labels it explicitly when editing" do
    get new_privacy_zone_path
    expect(response.body).not_to include("privacy_zone_active")

    zone = create(:privacy_zone, user: owner)
    get edit_privacy_zone_path(zone)
    expect(response.body).to include("Activer cette zone pour les futures publications")
  end

  it "does not allow access to another user's zone" do
    zone = create(:privacy_zone)

    get edit_privacy_zone_path(zone)

    expect(response).to have_http_status(:not_found)
  end

  it "renders the map picker with the numeric truth beside it" do
    get new_privacy_zone_path

    expect(response.body).to include('data-controller="zone-picker"')
    expect(response.body).to include('data-zone-picker-target="map"')
    expect(response.body).to include('data-zone-picker-target="latitude"')
    expect(response.body).to include('data-zone-picker-target="radiusRange"')
    expect(response.body).to include(I18n.t("privacy_zones.form.map_hint"))
    # Progressive enhancement: hidden without JS, numeric form stays usable.
    expect(response.body).to include("allure-map", "hidden")
  end

  it "paints the picker with the account's forced basemap" do
    owner.update!(theme: "dark", route_image_theme: "light")

    get new_privacy_zone_path

    map = Nokogiri::HTML(response.body).at_css('[data-zone-picker-target="map"]')
    expect(map["data-bs-theme"]).to eq("light")
    expect(response.body).to include('data-zone-picker-basemap-theme-value="light"')
  end

  it "prefills the slider from the edited zone" do
    zone = create(:privacy_zone, user: owner, radius_meters: 250)

    get edit_privacy_zone_path(zone)

    expect(response.body).to include('data-controller="zone-picker"')
    expect(response.body).to include('value="250"')
  end

  it "updates and deletes an owned zone" do
    zone = create(:privacy_zone, user: owner)

    patch privacy_zone_path(zone), params: { privacy_zone: { active: "0", radius_meters: "300" } }
    expect(response).to redirect_to(privacy_zones_path)
    expect(zone.reload).not_to be_active
    expect(zone.radius_meters).to eq(300)

    expect { delete privacy_zone_path(zone) }.to change(PrivacyZone, :count).by(-1)
  end
end
