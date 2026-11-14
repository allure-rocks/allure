# frozen_string_literal: true

require "rails_helper"
require "timeout"

RSpec.describe Allure::Toponyms::Selector do
  def candidate(name, kind, distance, coverage: 2_000, importance: 0.1, ancestors: [], climb_summit: false)
    {
      name:, kind:, distance:, elevation: 200.0, coverage:, importance:,
      occurrences: 2, ancestors:, climb_summit:
    }
  end

  it "selects three globally spaced steps for a 66 km route" do
    candidates = [
      candidate("Haversin", "village", 9_000),
      candidate("Cimefroide", "town", 20_000, coverage: 14_000),
      candidate("Hamois", "municipality", 33_000),
      candidate("Assesse", "town", 45_000, coverage: 12_000),
      candidate("Wépion", "village", 57_000)
    ]

    result = described_class.new(candidates:, total_distance: 66_000, start_name: "Valmorin", finish_name: "Rochelune").call

    expect(result.length).to eq(3)
    expect(result.pluck(:name)).to eq(%w[Cimefroide Assesse Wépion])
    expect(result.pluck(:rank)).to eq([ 1, 2, 3 ])
  end

  it "rejects endpoint labels and candidates inside endpoint margins" do
    candidates = [
      candidate("Valmorin", "village", 8_000),
      candidate("Near start", "town", 2_000),
      candidate("Middle", "town", 30_000),
      candidate("Rochelune", "city", 58_000)
    ]

    result = described_class.new(candidates:, total_distance: 60_000, start_name: "Valmorin", finish_name: "Rochelune").call

    expect(result.pluck(:name)).to eq([ "Middle" ])
  end

  it "does not select a place together with one of its ancestors" do
    candidates = [
      candidate("Pessoux", "village", 15_000, ancestors: %w[Cimefroide Dinant]),
      candidate("Cimefroide", "town", 30_000, coverage: 20_000),
      candidate("Assesse", "town", 50_000)
    ]

    result = described_class.new(candidates:, total_distance: 70_000).call

    expect(result.pluck(:name)).to include("Cimefroide", "Assesse")
    expect(result.pluck(:name)).not_to include("Pessoux")
  end

  it "adapts marker count to route length" do
    candidates = 5.times.map { |index| candidate("Town #{index}", "town", 2_000 + (index * 5_000)) }

    expect(described_class.new(candidates:, total_distance: 9_000).call.length).to be <= 1
    expect(described_class.new(candidates:, total_distance: 25_000).call.length).to be <= 2
  end

  it "keeps a climb summit even when it is close to the finish" do
    candidates = [
      candidate("Daussoulx", "village", 8_500),
      candidate("Gelbressée", "village", 14_700),
      candidate("Brumagne", "village", 25_700),
      candidate("Route Merveilleuse", "route", 35_700, climb_summit: true)
    ]

    result = described_class.new(candidates:, total_distance: 36_740, finish_name: "Rochelune").call

    expect(result.pluck(:name)).to include("Route Merveilleuse")
  end

  it "prefers an important landmark over a lower-value settlement" do
    candidates = [
      candidate("Citadel of Rochelune", "landmark", 8_000, importance: 0.4),
      candidate("Town", "town", 16_000),
      candidate("Village", "village", 24_000),
      candidate("Hamlet", "hamlet", 32_000)
    ]

    result = described_class.new(candidates:, total_distance: 40_000).call

    expect(result.pluck(:name)).to include("Citadel of Rochelune")
    expect(result.pluck(:name)).not_to include("Hamlet")
  end

  it "prefers a local place near its center over a containing town on a short route" do
    candidates = [
      candidate("Cimefroide", "town", 8_000, coverage: 15_000),
      candidate("Les Culées", "locality", 9_000, coverage: 800).merge(
        near_center: true, center_distance: 120.0, ancestors: [ "Cimefroide" ]
      )
    ]

    result = described_class.new(candidates:, total_distance: 20_000).call

    expect(result.pluck(:name)).to eq([ "Les Culées" ])
  end

  it "bounds global selection work for a large varied candidate set" do
    candidates = 200.times.map do |index|
      candidate("Place #{index}", %w[town village hamlet][index % 3], 10_000 + (index * 1_400))
    end

    result = Timeout.timeout(2) do
      described_class.new(candidates:, total_distance: 300_000).call
    end

    expect(result.length).to be <= 4
    expect(result.pluck(:distance)).to eq(result.pluck(:distance).sort)
  end
end
