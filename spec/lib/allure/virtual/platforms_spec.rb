# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "vips"

RSpec.describe Allure::Virtual::Platforms do
  # The world images are not committed (Zwift's artwork is not redistributable),
  # so the lookup examples build the files they ask for in a throwaway public
  # root. `available?` is what keeps a checkout without them on the ordinary
  # basemap.
  around do |example|
    Dir.mktmpdir do |root|
      @public_root = Pathname(root)
      Allure::Virtual::Platforms.fetch("zwift").venues.each do |venue|
        path = @public_root.join(venue.basemap.image)
        path.dirname.mkpath
        path.write("")
      end
      example.run
    end
  end

  # Web Mercator's y, the projection an image source is drawn in: a world's
  # rectangle is square in Mercator units when its image is square.
  def mercator(latitude)
    Math.log(Math.tan(Math::PI / 4 + latitude * Math::PI / 360))
  end

  # A platform built for one example, with a single world whose image is a
  # shipped file. Used to prove the lookup rules without touching the catalogue.
  def world_platform(key, longitude:, bounds:)
    Allure::Virtual::Platform.new(
      key:,
      name: key.capitalize,
      venues: [
        {
          key:,
          name: key.capitalize,
          longitude:,
          latitude: 45.0,
          radius_m: 5_000,
          basemap: {
            image: key == "far" ? "virtual_worlds/zwift/london-2fe1b8c8.webp" : "virtual_worlds/zwift/watopia-f4991742.webp",
            background: "#0884e2",
            bounds:
          }
        }
      ]
    )
  end

  describe ".creator_for" do
    it "names a registered platform from its complete FIT fingerprint" do
      expect(described_class.creator_for(manufacturer: 255, product: 22, serial_number: 1234)).to eq("EXR")
    end

    it "ignores a fingerprint whose declared fields do not all match" do
      expect(described_class.creator_for(manufacturer: 255, product: 22, serial_number: 99)).to be_nil
      expect(described_class.creator_for(manufacturer: 255, product: 0, serial_number: 1234)).to be_nil
    end

    it "is nil without a fingerprint" do
      expect(described_class.creator_for(nil)).to be_nil
      expect(described_class.creator_for(manufacturer: 1, product: 2337)).to be_nil
    end
  end

  describe ".for_creator" do
    it "matches the creator name case-insensitively and as a whole token" do
      expect(described_class.for_creator("exr")&.key).to eq("exr")
      expect(described_class.for_creator("EXR Game")&.key).to eq("exr")
    end

    it "does not match an unrelated creator" do
      expect(described_class.for_creator("ESP Rowing Monitor")).to be_nil
      expect(described_class.for_creator(nil)).to be_nil
    end
  end

  describe "the EXR venue catalogue" do
    it "locates the Long Beach world from a recorded start point" do
      venue = described_class.fetch("exr").venue_at(longitude: -118.1126, latitude: 33.7527)

      expect(venue&.name).to eq("Long Beach")
    end
  end

  describe "the Zwift catalogue" do
    it "names the platform from either manufacturer it writes" do
      expect(described_class.creator_for(manufacturer: 144, product: 0)).to eq("Zwift")
      expect(described_class.creator_for(manufacturer: 260, product: 0)).to eq("Zwift")
      expect(described_class.for_creator("Zwift")&.key).to eq("zwift")
    end

    it "locates Watopia from the start point the probe recorded" do
      venue = described_class.fetch("zwift").venue_at(longitude: 166.95251, latitude: -11.63555)

      expect(venue&.name).to eq("Watopia")
    end

    it "locates a real-world world from its own anchor" do
      venue = described_class.fetch("zwift").venue_at(longitude: -77.44177, latitude: 37.5394)

      expect(venue&.name).to eq("Richmond")
    end

    it "locates Paris on both the original circuit and the July 2026 expansion" do
      zwift = described_class.fetch("zwift")

      # The Champs-Élysées circuit, and the Montmartre climb the expansion added.
      expect(zwift.venue_at(longitude: 2.3075, latitude: 48.8698)&.name).to eq("Paris")
      expect(zwift.venue_at(longitude: 2.3431, latitude: 48.8867)&.name).to eq("Paris")
    end

    it "centres every world's anchor on its own image rectangle" do
      described_class.fetch("zwift").venues.each do |venue|
        west, south, east, north = venue.basemap.bounds

        expect(venue.longitude).to be_within(1e-5).of((west + east) / 2)
        expect(venue.latitude).to be_within(1e-5).of((south + north) / 2)
      end
    end

    it "has no sport fallback: the FIT sub-sport names the virtual sport" do
      expect(described_class.fetch("zwift").sport_slug).to be_nil
    end

    it "leaves a point outside every world unnamed" do
      expect(described_class.fetch("zwift").venue_at(longitude: 0, latitude: 0)).to be_nil
    end

    it "names a map image for every world, generated only on request" do
      described_class.fetch("zwift").venues.each do |venue|
        expect(venue.basemap).to be_present, "#{venue.key} has no basemap"
      end
    end

    it "keeps Zwift's artwork out of the repository" do
      # Generated on request by `bin/rails virtual:world_images`; never tracked.
      expect(Rails.root.join(".gitignore").read).to include("/public/virtual_worlds/zwift/*.webp")
    end

    it "draws each world image over a rectangle of its own proportions" do
      skip "world images are not generated in this checkout" if Rails.root.glob("public/virtual_worlds/zwift/*.webp").empty?

      described_class.fetch("zwift").venues.each do |venue|
        image = Vips::Image.new_from_file(Rails.root.join("public", venue.basemap.image).to_s)
        west, south, east, north = venue.basemap.bounds
        rectangle = ((east - west) * Math::PI / 180) / (mercator(north) - mercator(south))

        expect(image.width.to_f / image.height).to be_within(0.02 * rectangle).of(rectangle),
          "#{venue.key}'s image does not match its rectangle"
      end
    end

    it "locates the world map from a recorded point" do
      basemap = described_class.basemap_at(longitude: 166.95251, latitude: -11.63555, public_root: @public_root)

      expect(basemap.image).to eq("virtual_worlds/zwift/watopia-f4991742.webp")
      expect(basemap.background).to eq("#0884e2")
    end

    it "keeps a world's map just outside its published image" do
      # North of Watopia's rectangle but inside the radius that names the
      # world: a track that leaves the published bounds still draws on its
      # world's map, with the background colour around it.
      basemap = described_class.basemap_at(longitude: 166.955, latitude: -11.62, public_root: @public_root)

      expect(basemap.image).to eq("virtual_worlds/zwift/watopia-f4991742.webp")
    end

    it "has no map outside every world" do
      expect(described_class.basemap_at(longitude: 0, latitude: 0, public_root: @public_root)).to be_nil
    end

    it "draws no world map when its image is not generated" do
      Dir.mktmpdir do |empty_root|
        expect(described_class.basemap_at(longitude: 166.95251, latitude: -11.63555, public_root: empty_root)).to be_nil
      end
    end

    it "keeps every world image inside the radius that recognises the world" do
      described_class.fetch("zwift").venues.each do |venue|
        west, south, east, north = venue.basemap.bounds
        corners = [ [ west, south ], [ east, south ], [ east, north ], [ west, north ] ]

        corners.each do |longitude, latitude|
          expect(venue.distance_to(longitude:, latitude:)).to be <= venue.radius_m,
            "#{venue.key}'s image corner falls outside its radius"
        end
      end
    end

    it "resolves overlapping world images to the closest anchor" do
      near = world_platform("near", longitude: 6.0, bounds: [ 5.9, 44.9, 6.1, 45.1 ])
      far = world_platform("far", longitude: 6.02, bounds: [ 5.9, 44.9, 6.1, 45.1 ])
      allow(described_class).to receive(:all).and_return([ far, near ])

      expect(described_class.basemap_at(longitude: 6.004, latitude: 45.0, public_root: @public_root).image)
        .to eq("virtual_worlds/zwift/watopia-f4991742.webp")
    end

    it "prefers a world whose image contains the point over a closer anchor that does not" do
      near = world_platform("near", longitude: 6.0, bounds: [ 6.05, 45.05, 6.1, 45.1 ])
      far = world_platform("far", longitude: 6.03, bounds: [ 5.99, 44.99, 6.01, 45.01 ])
      allow(described_class).to receive(:all).and_return([ near, far ])

      expect(described_class.basemap_at(longitude: 6.0, latitude: 45.0, public_root: @public_root).image)
        .to eq("virtual_worlds/zwift/london-2fe1b8c8.webp")
    end
  end

  describe Allure::Virtual::Platform do
    # Genericity: a second provider is catalogue data, not a code path. This
    # entry is built here, with EXR never involved, to prove the pipeline only
    # ever asks the platform object.
    subject(:platform) do
      described_class.new(
        key: "tester",
        name: "Tester",
        fit_fingerprints: [ { manufacturer: 4000 } ],
        creator_aliases: [ "tester" ],
        sport_slug: "cycling_virtual",
        venues: [
          { key: "home", name: "Test World", longitude: 6.0, latitude: 45.0, radius_m: 1_000 },
          { key: "far", name: "Far World", longitude: 6.02, latitude: 45.0, radius_m: 1_000 }
        ]
      )
    end

    it "matches a partial fingerprint on the declared fields alone" do
      expect(platform.matches_file_id?(manufacturer: 4000, product: 7)).to be(true)
      expect(platform.matches_file_id?(manufacturer: 4001)).to be(false)
    end

    it "matches a creator alias exactly or as a token" do
      expect(platform.matches_creator?("Tester")).to be(true)
      expect(platform.matches_creator?("Tester Companion")).to be(true)
      expect(platform.matches_creator?("Contester")).to be(false)
    end

    it "locates a point inside a world radius" do
      venue = platform.venue_at(longitude: 6.004, latitude: 45.004)

      expect(venue&.name).to eq("Test World")
    end

    it "returns the closest world when two radii overlap" do
      venue = platform.venue_at(longitude: 6.0105, latitude: 45.0)

      expect(venue&.name).to eq("Far World")
    end

    it "does not locate a point outside every radius" do
      expect(platform.venue_at(longitude: 6.5, latitude: 45.0)).to be_nil
    end
  end
end
