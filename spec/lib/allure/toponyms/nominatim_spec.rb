# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Toponyms::Nominatim do
  subject(:client) { described_class.new(base_url: "https://geocoding.test") }

  def stub_reverse(body:, status: 200, zoom: 14)
    stub_request(:get, "https://geocoding.test/reverse")
      .with(query: hash_including("format" => "jsonv2", "zoom" => zoom.to_s))
      .to_return(status:, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "normalizes the complete settlement hierarchy" do
    stub_reverse(body: {
      "category" => "place", "type" => "hamlet", "addresstype" => "hamlet",
      "name" => "Trisogne", "importance" => 0.13,
      "address" => {
        "hamlet" => "Trisogne", "village" => "Pessoux", "town" => "Cimefroide",
        "county" => "Dinant", "state" => "Rochelune", "country" => "Belgique"
      }
    })

    result = client.reverse(longitude: 5.1609864, latitude: 50.2795688)

    expect(result[:feature]).to include(name: "Trisogne", kind: "hamlet")
    expect(result[:hierarchy]).to eq([
      { name: "Trisogne", kind: "hamlet", ancestors: %w[Pessoux Cimefroide Dinant Rochelune] },
      { name: "Pessoux", kind: "village", ancestors: %w[Cimefroide Dinant Rochelune] },
      { name: "Cimefroide", kind: "town", ancestors: %w[Dinant Rochelune] },
      { name: "Dinant", kind: "county", ancestors: %w[Rochelune] },
      { name: "Rochelune", kind: "state", ancestors: [] }
    ])
  end

  it "keeps a directly named summit in addition to its hierarchy" do
    stub_reverse(body: {
      "category" => "natural", "type" => "peak", "addresstype" => "peak",
      "name" => "Signal de Botrange", "importance" => 0.16,
      "address" => { "village" => "Robertville", "municipality" => "Waimes", "state" => "Liège" }
    })

    result = client.reverse(longitude: 6.0925, latitude: 50.5015)

    expect(result[:feature]).to eq(
      name: "Signal de Botrange", kind: "summit", importance: 0.16,
      ancestors: %w[Robertville Waimes Liège], osm_type: nil, osm_id: nil
    )
  end

  it "normalizes named major historic features as landmarks" do
    landmark_types = [
      [ "historic", "castle" ],
      [ "historic", "fort" ],
      [ "historic", "fortification" ],
      [ "historic", "monument" ],
      [ "historic", "memorial" ],
      [ "military", "fortification" ]
    ]

    landmark_types.each_with_index do |(category, type), index|
      longitude = 5.0 + index
      stub_request(:get, "https://geocoding.test/reverse")
        .with(query: hash_including("lon" => longitude.to_s, "lat" => "50.0", "zoom" => "14"))
        .to_return(
          status: 200,
          body: {
            "category" => category, "type" => type, "addresstype" => category,
            "name" => "Landmark #{index}", "importance" => 0.4,
            "osm_type" => "way", "osm_id" => index + 1,
            "address" => { "city" => "Rochelune" }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.reverse(longitude:, latitude: 50.0)

      expect(result[:feature]).to include(name: "Landmark #{index}", kind: "landmark", importance: 0.4)
    end
  end

  it "does not classify every historic feature as a landmark" do
    stub_reverse(body: {
      "category" => "historic", "type" => "archaeological_site", "addresstype" => "historic",
      "name" => "Unnamed site", "address" => { "city" => "Rochelune" }
    })

    result = client.reverse(longitude: 5.0, latitude: 50.0)

    expect(result[:feature]).to be_nil
    expect(result[:hierarchy]).to include(a_hash_including(name: "Rochelune", kind: "city"))
  end

  it "drops an unnamed micro-feature but keeps its useful hierarchy" do
    stub_reverse(body: {
      "category" => "man_made", "type" => "tower", "addresstype" => "man_made", "name" => "",
      "address" => { "village" => "Ovifat", "municipality" => "Waimes", "state" => "Liège" }
    })

    result = client.reverse(longitude: 6.0925, latitude: 50.5015)

    expect(result[:feature]).to be_nil
    expect(result[:hierarchy].first).to include(name: "Ovifat", kind: "village")
  end

  it "raises a retryable error for provider and network failures" do
    stub_reverse(body: {}, status: 500)
    expect { client.reverse(longitude: 5.0, latitude: 50.0) }
      .to raise_error(described_class::UnavailableError, /HTTP 500/)

    stub_request(:get, %r{\Ahttps://geocoding\.test/reverse}).to_raise(Net::ReadTimeout)
    expect { client.reverse(longitude: 5.1, latitude: 50.1) }
      .to raise_error(described_class::UnavailableError)
  end

  it "treats a missing reverse-geocoding result as unmapped" do
    stub_reverse(body: {}, status: 404)

    expect(client.reverse(longitude: 5.0, latitude: 50.0)).to be_nil
  end

  it "normalizes a named road at summit zoom" do
    stub_reverse(
      zoom: described_class::SUMMIT_ZOOM,
      body: {
        "category" => "highway", "type" => "secondary", "addresstype" => "road",
        "name" => "Route Merveilleuse", "importance" => 0.05,
        "address" => { "hamlet" => "La Plante", "city" => "Rochelune" }
      }
    )

    result = client.reverse(longitude: 4.8525, latitude: 50.4572, zoom: described_class::SUMMIT_ZOOM)

    expect(result[:feature]).to include(name: "Route Merveilleuse", kind: "route")
  end

  it "keeps local settlement centers and stable OSM references" do
    stub_reverse(body: {
      "category" => "place", "type" => "locality", "addresstype" => "locality",
      "name" => "Les Culées", "lat" => "50.2696002", "lon" => "5.1601598",
      "osm_type" => "node", "osm_id" => 7_140_047_176,
      "address" => { "locality" => "Les Culées", "village" => "Pessoux", "town" => "Cimefroide" }
    })

    result = client.reverse(longitude: 5.16, latitude: 50.27)

    expect(result[:feature]).to include(
      name: "Les Culées", kind: "locality", center_latitude: 50.2696002,
      center_longitude: 5.1601598, osm_type: "node", osm_id: 7_140_047_176
    )
  end

  it "resolves a settlement center inside a bounded route-local search" do
    stub_request(:get, "https://geocoding.test/search")
      .with(query: hash_including(
        "q" => "Pessoux, Cimefroide", "featureType" => "settlement", "bounded" => "1"
      ))
      .to_return(status: 200, body: [
        {
          "category" => "boundary", "type" => "administrative", "addresstype" => "village",
          "name" => "Pessoux", "lat" => "50.2825466", "lon" => "5.1707753"
        }
      ].to_json, headers: { "Content-Type" => "application/json" })

    center = client.settlement_center(
      name: "Pessoux", kind: "village", longitude: 5.16, latitude: 50.28, ancestors: [ "Cimefroide" ]
    )

    expect(center).to eq(center_latitude: 50.2825466, center_longitude: 5.1707753)
  end

  describe "#search" do
    def stub_search(body:, status: 200)
      stub_request(:get, "https://geocoding.test/search")
        .with(query: hash_including("q" => "Place Grenette, Grenoble", "format" => "jsonv2", "accept-language" => "fr"))
        .to_return(status:, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "normalizes labelled results and drops malformed rows" do
      stub_search(body: [
        { "display_name" => "Place Grenette, Grenoble, Isère, France", "lat" => "45.1907", "lon" => "5.7274" },
        { "display_name" => "Place Grenette, Grenoble, Isère, France", "lat" => "45.1908", "lon" => "5.7275" },
        { "display_name" => "", "lat" => "45.0", "lon" => "5.0" },
        { "display_name" => "Nowhere", "lat" => "95.0", "lon" => "5.0" },
        "garbage"
      ])

      results = client.search(query: "Place Grenette, Grenoble", language: "fr")

      expect(results).to eq([
        { label: "Place Grenette, Grenoble, Isère, France", latitude: 45.1907, longitude: 5.7274 }
      ])
    end

    it "answers no result for a refused query and raises when throttled" do
      stub_search(body: {}, status: 400)
      expect(client.search(query: "Place Grenette, Grenoble", language: "fr")).to eq([])

      stub_search(body: {}, status: 429)
      expect { client.search(query: "Place Grenette, Grenoble", language: "fr") }
        .to raise_error(described_class::UnavailableError, /HTTP 429/)
    end
  end
end
