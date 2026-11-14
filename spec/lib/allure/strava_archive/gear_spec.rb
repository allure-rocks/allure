# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::StravaArchive::Gear do
  it "keys bikes and shoes by name, ignoring case, a nameless item by « brand model »" do
    items = described_class.parse(
      bike: "Bike Name,Bike Brand,Bike Model,Bike Default Sport Types\nCanyon,Canyon,Grail,Ride\n",
      shoes: "Shoe Name,Shoe Brand,Shoe Model,Shoe Default Sport Types\nPegasus,Nike,Pegasus 41,Run\n,Hoka,Clifton,\n"
    )

    expect(items.keys).to contain_exactly("canyon", "pegasus", "hoka clifton")
    expect(items["hoka clifton"]).to have_attributes(name: "Hoka Clifton", kind: :shoes)
    expect(items["canyon"]).to have_attributes(kind: :bike, description: "Canyon Grail")
    expect(items["pegasus"]).to have_attributes(kind: :shoes, description: "Nike Pegasus 41")
  end

  it "reads a localized file by position and tolerates a missing one" do
    items = described_class.parse(bike: "Fahrradname,Fahrradmarke,Fahrradmodell\nRenner,Rose,Xlite\n", shoes: nil)

    expect(items["renner"]).to have_attributes(kind: :bike, brand: "Rose", model: "Xlite")
  end
end
