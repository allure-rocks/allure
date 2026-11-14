# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Allure::Virtual::Basemap do
  subject(:basemap) do
    described_class.new(
      image: "virtual_worlds/zwift/watopia-f4991742.webp",
      bounds: [ 166.87747, -11.74087, 167.03255, -11.62597 ],
      background: "#0884e2"
    )
  end

  it "contains a point inside its rectangle and rejects one outside" do
    expect(basemap.contains?(longitude: 166.95251, latitude: -11.63555)).to be(true)
    expect(basemap.contains?(longitude: 0, latitude: 0)).to be(false)
  end

  it "orders the corners for MapLibre's image source" do
    expect(basemap.coordinates).to eq([
      [ 166.87747, -11.62597 ],
      [ 167.03255, -11.62597 ],
      [ 167.03255, -11.74087 ],
      [ 166.87747, -11.74087 ]
    ])
  end

  it "serves the image from the application's own origin" do
    expect(basemap.path).to eq("/virtual_worlds/zwift/watopia-f4991742.webp")
    expect(basemap.to_map).to include(
      image: "/virtual_worlds/zwift/watopia-f4991742.webp",
      background: "#0884e2",
      darkBackground: "#032a48",
      attribution: "© Zwift"
    )
  end

  it "dims the world colour for the dark surface" do
    expect(basemap.dark_background).to eq("#032a48")
  end

  it "knows whether its image was generated under the public root" do
    Dir.mktmpdir do |root|
      expect(basemap.available?(root)).to be(false)

      path = Pathname(root).join(basemap.image)
      path.dirname.mkpath
      path.write("")

      expect(basemap.available?(root)).to be(true)
    end
  end

  it "refuses an inverted rectangle, a bad colour and a non-numeric bound" do
    expect do
      described_class.new(image: "x.webp", bounds: [ 2, 1, 1, 2 ], background: "#ffffff")
    end.to raise_error(ArgumentError, "invalid virtual world bounds")
    expect do
      described_class.new(image: "x.webp", bounds: [ 0, 0, 1, 1 ], background: "blue")
    end.to raise_error(ArgumentError, "invalid virtual world background")
    expect do
      described_class.new(image: "x.webp", bounds: [ 0, 0, 1, "north" ], background: "#ffffff")
    end.to raise_error(ArgumentError)
  end
end
