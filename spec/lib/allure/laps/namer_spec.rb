# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Laps::Namer do
  let(:workout) { create(:workout) }

  def toponymy(attributes = {})
    create(:workout_toponymy, workout:, **attributes)
  end

  it "names a climb from the nearest summit marker" do
    lap = build(:detected_lap, :climb, workout:, start_distance: 1_100.0, end_distance: 1_500.0)
    namer = described_class.new(lap:, toponymy: toponymy(markers: [
      { "distance" => 1_520.0, "name" => "Mont Faron", "kind" => "summit", "rank" => 1 },
      { "distance" => 1_540.0, "name" => "Toulon", "kind" => "city", "rank" => 2 }
    ]))

    expect(namer.call).to eq("Mont Faron")
  end

  it "prefers a marker inside the loop over the start place" do
    lap = build(:detected_lap, :loop, workout:, start_distance: 0.0, end_distance: 3_000.0)
    namer = described_class.new(lap:, toponymy: toponymy(markers: [
      { "distance" => 1_200.0, "name" => "Parc de la Tête d'Or", "kind" => "landmark", "rank" => 1 }
    ]))

    expect(namer.call).to eq("Parc de la Tête d'Or")
  end

  it "falls back to the start place for a loop with no marker inside" do
    lap = build(:detected_lap, :loop, workout:, start_distance: 0.0, end_distance: 3_000.0)
    namer = described_class.new(lap:, toponymy: toponymy(markers: []))

    expect(namer.call).to eq("Valmorin")
  end

  it "names a pause from a nearby marker" do
    lap = build(:detected_lap, workout:, start_distance: 4_500.0, end_distance: 5_000.0)
    namer = described_class.new(lap:, toponymy: toponymy(markers: [
      { "distance" => 4_800.0, "name" => "Cimefroide", "kind" => "town", "rank" => 1 }
    ]))

    expect(namer.call).to eq("Cimefroide")
  end

  it "uses a strict climb summit when no marker matches" do
    lap = build(:detected_lap, :climb, workout:, start_distance: 900.0, end_distance: 1_400.0)
    namer = described_class.new(lap:, toponymy: toponymy(samples: [
      { "distance" => 1_450.0, "elevation" => 800.0, "role" => "climb_summit",
        "result" => { "feature" => { "name" => "Pic de Château Renard", "kind" => "summit" } } }
    ], markers: []))

    expect(namer.call).to eq("Pic de Château Renard")
  end

  it "never names a route lap" do
    lap = build(:detected_lap, :route, workout:)
    namer = described_class.new(lap:, toponymy: toponymy)

    expect(namer.call).to be_nil
  end

  it "returns nothing while the toponymy is not usable" do
    lap = build(:detected_lap, workout:, start_distance: 0.0, end_distance: 1_000.0)
    namer = described_class.new(lap:, toponymy: toponymy(status: "pending"))

    expect(namer.call).to be_nil
  end
end
