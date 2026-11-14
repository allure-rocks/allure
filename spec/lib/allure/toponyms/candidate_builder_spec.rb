# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Toponyms::CandidateBuilder do
  def sample(distance, elevation: 100.0, latitude: 50.0, longitude: 5.0)
    { distance:, elevation:, latitude:, longitude:, role: "route" }
  end

  def result(feature: nil, hierarchy: [])
    { feature:, hierarchy: }
  end

  it "collapses repeated hierarchy values into one route passage" do
    samples = [ sample(10_000), sample(12_000, elevation: 130), sample(14_000) ]
    results = samples.map do
      result(hierarchy: [
        { name: "Cimefroide", kind: "town", ancestors: %w[Dinant Rochelune] },
        { name: "Dinant", kind: "county", ancestors: %w[Rochelune] }
      ])
    end

    candidates = described_class.new(samples:, results:).call
    ciney = candidates.find { it[:name] == "Cimefroide" }

    expect(ciney).to include(distance: 12_000, elevation: 130, coverage: 4_000.0, occurrences: 3)
    expect(ciney[:ancestors]).to contain_exactly("Dinant", "Rochelune")
  end

  it "uses a direct village at the start and a containing city for a finishing hamlet" do
    samples = [ sample(0), sample(60_000) ]
    results = [
      result(feature: { name: "Valmorin", kind: "village" }, hierarchy: [
        { name: "Valmorin", kind: "village" }, { name: "Marche-en-Famenne", kind: "municipality" }
      ]),
      result(hierarchy: [
        { name: "La Plante", kind: "hamlet" }, { name: "Rochelune", kind: "city" }
      ])
    ]

    context = described_class.new(samples:, results:).route_context(total_distance: 60_000)

    expect(context).to eq(
      start: { name: "Valmorin", kind: "village" },
      finish: { name: "Rochelune", kind: "city" }
    )
  end

  it "uses a local neighbourhood for endpoints on a short route" do
    samples = [ sample(0), sample(20_000) ]
    results = samples.map do
      result(
        feature: { name: "Habitat groupé Pa-d'zo l'Haye", kind: "neighbourhood" },
        hierarchy: [ { name: "Herbefays", kind: "hamlet" }, { name: "Durnal", kind: "village" } ]
      )
    end

    context = described_class.new(samples:, results:).route_context(total_distance: 20_000)

    expect(context).to eq(
      start: { name: "Habitat groupé Pa-d'zo l'Haye", kind: "neighbourhood" },
      finish: { name: "Habitat groupé Pa-d'zo l'Haye", kind: "neighbourhood" }
    )
  end

  it "uses a broad settlement for endpoints on a long route" do
    samples = [ sample(0), sample(100_000) ]
    results = samples.map do
      result(
        feature: { name: "Herbefays", kind: "hamlet" },
        hierarchy: [ { name: "Durnal", kind: "village" }, { name: "Dinant", kind: "municipality" } ]
      )
    end

    context = described_class.new(samples:, results:).route_context(total_distance: 100_000)

    expect(context).to eq(
      start: { name: "Durnal", kind: "village" },
      finish: { name: "Durnal", kind: "village" }
    )
  end

  it "keeps separate passages when a route leaves and later re-enters a place" do
    samples = [ sample(10_000), sample(20_000), sample(30_000) ]
    results = [
      result(hierarchy: [ { name: "Cimefroide", kind: "town" } ]),
      result(hierarchy: [ { name: "Assesse", kind: "village" } ]),
      result(hierarchy: [ { name: "Cimefroide", kind: "town" } ])
    ]

    candidates = described_class.new(samples:, results:).call.select { it[:name] == "Cimefroide" }

    expect(candidates.pluck(:distance)).to eq([ 10_000, 30_000 ])
    expect(candidates.pluck(:coverage)).to eq([ 0.0, 0.0 ])
  end

  it "preserves the climb summit role on a place candidate" do
    samples = [ sample(10_000), sample(12_000).merge(role: "climb_summit") ]
    results = samples.map do
      result(feature: { name: "Route Merveilleuse", kind: "route" })
    end

    candidate = described_class.new(samples:, results:).call.first

    expect(candidate).to include(name: "Route Merveilleuse", climb_summit: true)
  end

  it "keeps a landmark as a marker without using it as endpoint context" do
    samples = [ sample(0), sample(20_000) ]
    results = samples.map do
      result(
        feature: { name: "Citadel of Rochelune", kind: "landmark", importance: 0.4 },
        hierarchy: [ { name: "Rochelune", kind: "city", ancestors: [] } ]
      )
    end
    builder = described_class.new(samples:, results:)

    candidate = builder.call.find { it[:name] == "Citadel of Rochelune" }

    expect(candidate).to include(kind: "landmark", importance: 0.4)
    expect(builder.route_context(total_distance: 20_000)).to eq(
      start: { name: "Rochelune", kind: "city" },
      finish: { name: "Rochelune", kind: "city" }
    )
  end

  it "replaces the provider feature with a closer settlement of the preferred tier" do
    samples = [
      sample(0.0, latitude: 45.62390, longitude: 2.82464),
      sample(10_786.3, latitude: 45.68252, longitude: 2.84163)
    ]
    results = [
      result(
        feature: {
          name: "La Montagne du Cros", kind: "isolated_dwelling",
          center_latitude: 45.63991, center_longitude: 2.82280
        },
        hierarchy: [ { name: "Orcival", kind: "village" } ]
      ),
      result(
        feature: {
          name: "Puy Raynaud", kind: "isolated_dwelling",
          center_latitude: 45.67972, center_longitude: 2.84246
        },
        hierarchy: [ { name: "Les Planchettes", kind: "hamlet" }, { name: "Orcival", kind: "village" } ]
      )
    ]
    centers = [
      { name: "Orcival", kind: "village", latitude: 45.68296, longitude: 2.84232 },
      { name: "Les Planchettes", kind: "hamlet", latitude: 45.67121, longitude: 2.84233 }
    ]

    context = described_class.new(samples:, results:).route_context(total_distance: 10_786.3, centers:)

    expect(context.fetch(:finish)).to eq(name: "Orcival", kind: "village", center_distance: 72.6)
    expect(context.fetch(:start)).to eq(name: "La Montagne du Cros", kind: "isolated_dwelling", center_distance: 1786.0)
  end

  it "keeps the provider feature when no settlement is closer to the endpoint" do
    samples = [ sample(0.0), sample(10_000.0) ]
    results = [
      result(
        feature: { name: "Le Rivier", kind: "isolated_dwelling", center_latitude: 50.001, center_longitude: 5.0 },
        hierarchy: [ { name: "Vaujany", kind: "village" } ]
      ),
      result(
        feature: { name: "Le Rivier", kind: "isolated_dwelling", center_latitude: 50.001, center_longitude: 5.0 },
        hierarchy: [ { name: "Vaujany", kind: "village" } ]
      )
    ]
    centers = [ { name: "Vaujany", kind: "village", latitude: 50.006, longitude: 5.0 } ]

    context = described_class.new(samples:, results:).route_context(total_distance: 10_000.0, centers:)

    expect(context.fetch(:start)).to eq(name: "Le Rivier", kind: "isolated_dwelling", center_distance: 111.2)
    expect(context.fetch(:finish)).to eq(name: "Le Rivier", kind: "isolated_dwelling", center_distance: 111.2)
  end

  it "reports the provider feature centre distance when only the feature carries a centre" do
    samples = [ sample(0.0), sample(20_000.0, latitude: 50.2) ]
    results = samples.map do
      result(feature: { name: "Puy Raynaud", kind: "isolated_dwelling", center_latitude: 50.1997, center_longitude: 5.0 })
    end

    context = described_class.new(samples:, results:).route_context(total_distance: 20_000.0)

    expect(context.fetch(:finish)).to eq(name: "Puy Raynaud", kind: "isolated_dwelling", center_distance: 33.4)
  end
end
