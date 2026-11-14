# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::StravaArchive::ActivityTypes do
  it "maps the API names, the English labels and the localized ones" do
    expect(described_class.slug_for("Ride")).to eq("cycling")
    expect(described_class.slug_for("VirtualRide")).to eq("cycling_virtual")
    expect(described_class.slug_for("Virtual Ride")).to eq("cycling_virtual")
    expect(described_class.slug_for("E-Mountain Bike Ride")).to eq("mountain_biking_electric")
    expect(described_class.slug_for("Weight Training")).to eq("strength_training")
    expect(described_class.slug_for("Course à pied")).to eq("running")
    expect(described_class.slug_for("Radfahrt")).to eq("cycling")
    expect(described_class.slug_for("Training")).to eq("fitness")
    expect(described_class.slug_for("Swim")).to eq("open_water_swimming")
  end

  it "falls back to an exact alias of the catalog" do
    expect(described_class.slug_for("ski de fond")).to eq("skiing_cross_country")
  end

  it "never guesses from part of a label" do
    expect(described_class.slug_for("Rock Climbing")).to be_nil
    expect(described_class.slug_for("Golf")).to be_nil
    expect(described_class.slug_for(nil)).to be_nil
  end

  it "only names sports of the catalog" do
    expect(described_class::TYPES.keys).to all(be_in(Allure::SportPalette::ALLURE_ICONS))
  end
end
