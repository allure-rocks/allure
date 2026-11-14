# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ToponymyEnricher do
  FakeClient = Data.define(:base_url, :responses) do
    def reverse(longitude:, latitude:, zoom:)
      responses.shift
    end

    def settlement_center(name:, kind:, longitude:, latitude:, ancestors:)
      nil
    end
  end

  PersistenceClient = Data.define(:base_url) do
    def reverse(longitude:, latitude:, zoom:)
      return unless zoom == Allure::Toponyms::Nominatim::MARKER_ZOOM

      position = latitude.round(2)
      if position == 50.0
        { feature: { name: "Start", kind: "village" }, hierarchy: [] }
      elsif position == 50.2
        { feature: nil, hierarchy: [ { name: "Finish", kind: "city", ancestors: [] } ] }
      elsif position.between?(50.01, 50.09)
        feature = { name: "Middleton", kind: "locality", ancestors: [ "Province" ] }
        feature.merge!(center_latitude: 50.08, center_longitude: 5.0) if position == 50.08
        { feature:, hierarchy: [] }
      else
        { feature: { name: "Further", kind: "hamlet", ancestors: [ "Province" ] }, hierarchy: [] }
      end
    end

    def settlement_center(name:, kind:, longitude:, latitude:, ancestors:)
      nil
    end
  end

  AdaptiveClient = Data.define(:base_url, :zooms) do
    def reverse(longitude:, latitude:, zoom:)
      zooms << zoom
      case zoom
      when Allure::Toponyms::Nominatim::MARKER_ZOOM
        { feature: nil, hierarchy: [ { name: "Cimefroide", kind: "town", ancestors: [] } ] }
      when Allure::Toponyms::Nominatim::LOCALITY_ZOOM
        {
          feature: { name: "Les Culées", kind: "locality", ancestors: [ "Cimefroide" ] },
          hierarchy: [ { name: "Cimefroide", kind: "town", ancestors: [] } ]
        }
      else
        raise "unexpected route-detail lookup"
      end
    end

    def settlement_center(name:, kind:, longitude:, latitude:, ancestors:)
      nil
    end
  end

  RouteDetailClient = Data.define(:base_url, :zooms) do
    def reverse(longitude:, latitude:, zoom:)
      zooms << zoom
      if zoom == Allure::Toponyms::Nominatim::ROUTE_ZOOM
        {
          feature: { name: "Rue de la Fontaine", kind: "route", ancestors: [ "Cimefroide" ] },
          hierarchy: [ { name: "Cimefroide", kind: "town", ancestors: [] } ]
        }
      else
        { feature: nil, hierarchy: [ { name: "Cimefroide", kind: "town", ancestors: [] } ] }
      end
    end

    def settlement_center(name:, kind:, longitude:, latitude:, ancestors:)
      nil
    end
  end

  EndpointAdaptiveClient = Data.define(:base_url, :zooms) do
    def reverse(longitude:, latitude:, zoom:)
      zooms << zoom
      case zoom
      when Allure::Toponyms::Nominatim::MARKER_ZOOM
        {
          feature: {
            name: "Herbefays", kind: "hamlet", ancestors: [ "Durnal" ],
            center_latitude: 50.01, center_longitude: 5.0
          },
          hierarchy: [ { name: "Durnal", kind: "village", ancestors: [] } ]
        }
      when Allure::Toponyms::Nominatim::LOCALITY_ZOOM
        {
          feature: {
            name: "Habitat groupé Pa-d'zo l'Haye", kind: "neighbourhood", ancestors: [ "Durnal" ],
            center_latitude: 50.0, center_longitude: 5.0
          },
          hierarchy: [ { name: "Durnal", kind: "village", ancestors: [] } ]
        }
      else
        raise "unexpected route-detail lookup"
      end
    end

    def settlement_center(name:, kind:, longitude:, latitude:, ancestors:)
      nil
    end
  end

  LandmarkClient = Data.define(:base_url, :zooms) do
    def reverse(longitude:, latitude:, zoom:)
      zooms << zoom
      {
        feature: { name: "Citadel of Rochelune", kind: "landmark", importance: 0.4 },
        hierarchy: [ { name: "Rochelune", kind: "city", ancestors: [] } ]
      }
    end

    def settlement_center(name:, kind:, longitude:, latitude:, ancestors:)
      nil
    end
  end

  EndpointCenterClient = Data.define(:base_url, :centres) do
    def reverse(longitude:, latitude:, zoom:)
      case latitude.round(2)
      when 50.0
        {
          feature: {
            name: "La Montagne du Cros", kind: "isolated_dwelling",
            center_latitude: 50.016, center_longitude: 5.0
          },
          hierarchy: [ { name: "Orcival", kind: "village", ancestors: [] } ]
        }
      when 50.2
        {
          feature: {
            name: "Puy Raynaud", kind: "isolated_dwelling",
            center_latitude: 50.1997, center_longitude: 5.0
          },
          hierarchy: [
            { name: "Les Planchettes", kind: "hamlet", ancestors: [] },
            { name: "Orcival", kind: "village", ancestors: [] }
          ]
        }
      else
        {
          feature: { name: "Chemin", kind: "route", center_latitude: latitude, center_longitude: 5.0 },
          hierarchy: [ { name: "Orcival", kind: "village", ancestors: [] } ]
        }
      end
    end

    def settlement_center(name:, kind:, longitude:, latitude:, ancestors:)
      centres[[ name, kind ]]
    end
  end

  ReselectClient = Data.define(:base_url, :centres) do
    def reverse(longitude:, latitude:, zoom:)
      raise "the stored samples must be reused"
    end

    def settlement_center(name:, kind:, longitude:, latitude:, ancestors:)
      centres[[ name, kind ]]
    end
  end

  FailingCenterClient = Data.define(:base_url) do
    def reverse(longitude:, latitude:, zoom:)
      raise "the stored samples must be reused"
    end

    def settlement_center(name:, kind:, longitude:, latitude:, ancestors:)
      raise Allure::Toponyms::Nominatim::UnavailableError, "timeout"
    end
  end

  let(:workout) { create(:workout, distance: 20_000.0, points_count: 21) }
  let!(:track_segment) do
    points = 21.times.map do |index|
      { "t" => index * 60, "d" => index * 1_000.0, "lat" => 50.0 + (index * 0.01), "lon" => 5.0, "ele" => 100.0 + index }
    end
    create(:track_segment, workout:, distance: 20_000.0, points:, points_count: points.length)
  end

  it "uses dense geocoding settings for background enrichment" do
    expect(described_class::GEOCODING_TIMEOUT).to eq(5.minutes)
  end

  it "paces its requests to the configured interval" do
    client = LandmarkClient.new("https://geocoding.test", [])
    waits = []
    now = 0.0

    described_class.new(
      workout:, client:, sleeper: ->(seconds) { waits << seconds }, clock: -> { now }, request_interval: 0.25
    ).call

    expect(waits.length).to be >= client.zooms.length - 1
    expect(waits).to be_present.and all(eq(0.25))
  end

  it "uses locality detail on a short route and stops before route detail when it finds a local feature" do
    client = AdaptiveClient.new("https://geocoding.test", [])

    toponymy = described_class.new(workout:, client:, sleeper: ->(*) { }).call

    expect(client.zooms).to include(Allure::Toponyms::Nominatim::LOCALITY_ZOOM)
    expect(client.zooms).not_to include(Allure::Toponyms::Nominatim::ROUTE_ZOOM)
    expect(toponymy.samples.filter_map { it.dig("result", "feature", "name") }).to include("Les Culées")
  end

  it "uses a named route when locality detail remains too broad" do
    client = RouteDetailClient.new("https://geocoding.test", [])

    toponymy = described_class.new(workout:, client:, sleeper: ->(*) { }).call

    expect(client.zooms).to include(Allure::Toponyms::Nominatim::ROUTE_ZOOM)
    expect(toponymy.markers.pluck("name")).to include("Rue de la Fontaine")
  end

  it "refines distant short-route endpoints to a local neighbourhood" do
    client = EndpointAdaptiveClient.new("https://geocoding.test", [])

    toponymy = described_class.new(workout:, client:, sleeper: ->(*) { }).call

    expect(client.zooms).to include(Allure::Toponyms::Nominatim::LOCALITY_ZOOM)
    expect(toponymy.start_place).to eq(
      "name" => "Habitat groupé Pa-d'zo l'Haye", "kind" => "neighbourhood", "center_distance" => 0.0
    )
    expect(toponymy.finish_place).to eq(
      "name" => "Habitat groupé Pa-d'zo l'Haye", "kind" => "neighbourhood", "center_distance" => 22_239.0
    )
  end

  it "keeps a recognized landmark at marker detail without replacing it with a settlement" do
    client = LandmarkClient.new("https://geocoding.test", [])

    toponymy = described_class.new(workout:, client:, sleeper: ->(*) { }).call

    expect(client.zooms).not_to include(Allure::Toponyms::Nominatim::LOCALITY_ZOOM)
    expect(toponymy.markers).to include(a_hash_including("name" => "Citadel of Rochelune", "kind" => "landmark"))
  end

  it "replaces a way-side feature with the closer settlement centre at the finish" do
    client = EndpointCenterClient.new(
      "https://geocoding.test",
      { [ "Orcival", "village" ] => { center_latitude: 50.2, center_longitude: 5.0 } }
    )

    toponymy = described_class.new(workout:, client:, sleeper: ->(*) { }).call

    expect(toponymy).to be_ready
    expect(toponymy.start_place).to include("name" => "La Montagne du Cros", "kind" => "isolated_dwelling")
    expect(toponymy.start_place["center_distance"]).to eq(1779.1)
    expect(toponymy.finish_place).to include("name" => "Orcival", "kind" => "village", "center_distance" => 0.0)
    expect(workout.reload.places.pluck("name")).to include("Orcival")
  end

  def result(name, kind, ancestors: [])
    {
      feature: nil,
      hierarchy: [ { name:, kind:, ancestors: } ]
    }
  end

  it "persists normalized samples, endpoint context and selected markers" do
    samples = Allure::Toponyms::SampleTrack.new(segments: [ track_segment ]).call
    client = PersistenceClient.new("https://geocoding.test")
    sleeper = instance_double(Proc, call: nil)

    toponymy = described_class.new(workout:, client:, sleeper:).call

    expect(toponymy).to be_ready
    expect(toponymy.provider).to eq("https://geocoding.test")
    expect(toponymy.sampled_points_count).to eq(samples.length)
    expect(toponymy.start_place).to include("name" => "Start")
    expect(toponymy.finish_place).to include("name" => "Finish")
    expect(toponymy.markers).not_to be_empty
    expect(toponymy.markers).to include(a_hash_including("name" => "Middleton", "distance" => 8_000.0))
    expect(toponymy.samples.first.keys).to contain_exactly("distance", "elevation", "role", "result")
    expect(sleeper).to have_received(:call).at_least(:once)
  end

  it "names detected laps once the toponymy lands" do
    lap = create(:detected_lap, :loop, workout:, start_distance: 0.0, end_distance: 9_000.0)
    client = PersistenceClient.new("https://geocoding.test")

    described_class.new(workout:, client:, sleeper: ->(*) { }).call

    expect(lap.reload.name).to eq("Middleton")
  end

  it "assembles the workout places from the stored toponymy without any extra request" do
    client = PersistenceClient.new("https://geocoding.test")

    described_class.new(workout:, client:, sleeper: ->(*) { }).call

    places = workout.reload.places
    expect(places.first).to include("name" => "Start")
    expect(places.last).to include("name" => "Finish")
    expect(places.length).to be <= Workouts::PlaceNamer::PLACE_LIMIT
    expect(places).to all(satisfy { |place| place.keys.sort == %w[kind name] })
    expect(workout.place_names.pluck(:name)).to include("Start", "Finish")
    expect(workout.toponymy.places_algorithm_version).to eq(Workouts::PlaceNamer::ALGORITHM_VERSION)
  end

  it "records a partial result when some lookups fail" do
    samples = Allure::Toponyms::SampleTrack.new(segments: [ track_segment ]).call
    client = FakeClient.new("https://geocoding.test", [ result("Start", "village") ] + Array.new(samples.length - 1))

    toponymy = described_class.new(workout:, client:, sleeper: ->(*) { }).call

    expect(toponymy).to be_partial
  end

  it "is idempotent once the current algorithm has completed" do
    existing = create(:workout_toponymy, workout:)
    client = instance_double(Allure::Toponyms::Nominatim, base_url: "https://geocoding.test")
    expect(client).not_to receive(:reverse)

    result = described_class.new(workout:, client:).call

    expect(result).to eq(existing)
  end

  it "marks toponymy unavailable when no client is configured" do
    toponymy = described_class.new(workout:, client: nil).call

    expect(toponymy).to be_unavailable
  end

  it "requires explicit configuration before sending route coordinates" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GEOCODING_BASE_URL").and_return(nil)

    toponymy = described_class.new(workout:).call

    expect(toponymy).to be_unavailable
  end

  it "keeps retryable provider failures pending" do
    client = instance_double(Allure::Toponyms::Nominatim, base_url: "https://geocoding.test")
    allow(client).to receive(:reverse).and_raise(Allure::Toponyms::Nominatim::UnavailableError, "timeout")

    expect do
      described_class.new(workout:, client:, sleeper: ->(*) { }).call
    end.to raise_error(Allure::Toponyms::Nominatim::UnavailableError)

    expect(workout.toponymy.reload).to be_pending
    expect(workout.toponymy.last_error).to eq("timeout")
  end

  describe "offline endpoint re-selection of a version-8 toponymy" do
    let(:markers) do
      [
        { "distance" => 10_000.0, "elevation" => 200.0, "name" => "Orcival", "kind" => "village", "rank" => 1 },
        { "distance" => 15_000.0, "elevation" => 220.0, "name" => "Grande fontaine", "kind" => "spring", "rank" => 2 }
      ]
    end

    let!(:toponymy) do
      stored = Allure::Toponyms::SampleTrack.new(segments: [ track_segment ]).call
      create(
        :workout_toponymy,
        workout:,
        status: "ready",
        algorithm_version: 8,
        sampled_points_count: stored.length,
        markers:,
        samples: stored.map { |sample| stored_sample(sample) }
      )
    end

    def stored_sample(sample)
      {
        "distance" => sample.fetch(:distance),
        "elevation" => sample[:elevation],
        "role" => sample.fetch(:role),
        "result" => stored_result(sample)
      }
    end

    def stored_result(sample)
      case sample.fetch(:latitude).round(2)
      when 50.0
        {
          "feature" => {
            "name" => "La Montagne du Cros", "kind" => "isolated_dwelling",
            "center_latitude" => 50.016, "center_longitude" => 5.0
          },
          "hierarchy" => [ { "name" => "Orcival", "kind" => "village", "ancestors" => [] } ]
        }
      when 50.2
        {
          "feature" => {
            "name" => "Puy Raynaud", "kind" => "isolated_dwelling",
            "center_latitude" => 50.1997, "center_longitude" => 5.0
          },
          "hierarchy" => [
            { "name" => "Les Planchettes", "kind" => "hamlet", "ancestors" => [] },
            { "name" => "Orcival", "kind" => "village", "ancestors" => [] }
          ]
        }
      else
        { "feature" => nil, "hierarchy" => [ { "name" => "Chemin", "kind" => "route", "ancestors" => [] } ] }
      end
    end

    it "re-selects the endpoint labels offline, without a reverse request" do
      client = ReselectClient.new(
        "https://geocoding.test",
        { [ "Orcival", "village" ] => { center_latitude: 50.2, center_longitude: 5.0 } }
      )

      result = described_class.new(workout:, client:, sleeper: ->(*) { }).call

      expect(result).to be_ready
      expect(result.algorithm_version).to eq(described_class::ALGORITHM_VERSION)
      expect(result.start_place).to include("name" => "La Montagne du Cros", "kind" => "isolated_dwelling")
      expect(result.finish_place).to include("name" => "Orcival", "kind" => "village", "center_distance" => 0.0)
      expect(result.markers.pluck("name")).to eq([ "Grande fontaine" ])
      expect(workout.reload.places.pluck("name")).to include("La Montagne du Cros", "Orcival")
      expect(workout.place_names.pluck(:name)).to include("Orcival")
    end

    it "re-geocodes in full when the stored samples no longer line up" do
      rows = toponymy.reload.samples.map { |row| row.merge("distance" => row["distance"] + 250.0) }
      toponymy.update_columns(samples: rows)
      client = PersistenceClient.new("https://geocoding.test")

      result = described_class.new(workout:, client:, sleeper: ->(*) { }).call

      expect(result).to be_ready
      expect(result.start_place).to include("name" => "Start")
      expect(result.finish_place).to include("name" => "Finish")
    end

    it "keeps a retryable re-selection pending" do
      client = FailingCenterClient.new("https://geocoding.test")

      expect do
        described_class.new(workout:, client:, sleeper: ->(*) { }).call
      end.to raise_error(Allure::Toponyms::Nominatim::UnavailableError)

      expect(toponymy.reload).to be_pending
      expect(toponymy.last_error).to eq("timeout")
    end
  end
end
