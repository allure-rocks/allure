# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Fit::Devices do
  # FIT SDK profile 21.218.0 `manufacturer`. The version-2 table named nine of
  # these wrong (Polar under 98, Stages under 68, Sigma under 69…).
  it "follows the FIT SDK manufacturer codes" do
    expect({
      1 => described_class.manufacturer(1),
      32 => described_class.manufacturer(32),
      38 => described_class.manufacturer(38),
      51 => described_class.manufacturer(51),
      68 => described_class.manufacturer(68),
      69 => described_class.manufacturer(69),
      70 => described_class.manufacturer(70),
      95 => described_class.manufacturer(95),
      98 => described_class.manufacturer(98),
      107 => described_class.manufacturer(107),
      115 => described_class.manufacturer(115),
      123 => described_class.manufacturer(123),
      267 => described_class.manufacturer(267),
      294 => described_class.manufacturer(294)
    }).to eq(
      1 => "Garmin", 32 => "Wahoo Fitness", 38 => "O-Synce", 51 => "4iiii", 68 => "CatEye",
      69 => "Stages Cycling", 70 => "Sigma Sport", 95 => "Stryd", 98 => "BSX Athletics",
      107 => "Magene", 115 => "iGPSPORT", 123 => "Polar", 267 => "Bryton", 294 => "COROS"
    )
  end

  it "names no device for the development manufacturer" do
    expect(described_class.manufacturer(255)).to be_nil
  end

  it "reads the product as a Garmin product for Garmin, Dynastream and Tacx" do
    expect([ 1, 13, 15, 89 ].map { |code| described_class.product(code, 3122) }).to all(eq("Garmin Edge 830"))
  end

  it "reads another maker's product in its own numbering" do
    expect(described_class.product(263, 12)).to eq("Favero Assioma Duo")
    expect(described_class.product(294, 3122)).to be_nil
  end

  it "is nil without a product code" do
    expect(described_class.product(1, nil)).to be_nil
  end

  it "keeps every display name short and printable" do
    names = described_class::MANUFACTURERS.values + described_class::GARMIN_PRODUCTS.values +
      described_class::PRODUCTS.values.flat_map(&:values)

    expect(names).to all(match(/\A\S(.{0,58}\S)?\z/))
  end
end
