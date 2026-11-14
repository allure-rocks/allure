# frozen_string_literal: true

module Allure
  module Virtual
    # The virtual-platform catalog (PLAN_VIRTUAL.md). Everything virtual that
    # the pipeline knows lives here: adding a provider is one entry, and no
    # other file names it. The entry bundles its FIT fingerprint, its creator
    # aliases, the sport to use when the file carries none, and the worlds it
    # renders. A provider without worlds (a pure ergometer) lists none.
    #
    # EXR is identified by the fingerprint it writes on every file: the FIT
    # `development` manufacturer (255) with product 22 and serial number 1234,
    # and by its creator name in exports that keep one.
    module Platforms
      ENTRIES = [
        {
          key: "exr",
          name: "EXR",
          fit_fingerprints: [ { manufacturer: 255, product: 22, serial_number: 1234 } ],
          creator_aliases: %w[exr exrgame],
          sport_slug: "rowing_virtual",
          venues: [
            { key: "boston", name: "Boston", longitude: -71.13, latitude: 42.355, radius_m: 6_000 },
            { key: "bled", name: "Bled", longitude: 14.091, latitude: 46.362, radius_m: 3_000 },
            { key: "henley", name: "Henley", longitude: -0.885, latitude: 51.545, radius_m: 3_000 },
            { key: "exr_world", name: "EXR World", longitude: 4.14, latitude: 51.479, radius_m: 3_000 },
            { key: "long_beach", name: "Long Beach", longitude: -118.1218, latitude: 33.7554, radius_m: 6_000 }
          ]
        },
        {
          # Zwift writes manufacturer 144 or 260 and no product name, so the
          # fingerprint is the manufacturer alone. The FIT `sport`/`sub_sport`
          # pair (`virtual_activity`) already names the virtual sport, so the
          # entry has no fallback. The world anchors and the basemap rectangles
          # are the bounding boxes of the MIT-licensed `zwift-data` package
          # (andipaetzold/zwift-data, `src/worlds.ts`), reduced to a centre and
          # a radius that contains the whole map; Gravel Mountain (world id 12)
          # has no published bounds yet and is left out rather than guessed.
          #
          # Paris is the one exception: its July 2026 expansion map has no
          # published rectangle, so the rectangle is the previous one shifted by
          # a quarter of its size north and east, where the two maps register
          # exactly (PLAN_VIRTUAL.md §2.1). The anchor is its centre, like every
          # other world.
          #
          # Each `basemap` is the world's published map image, generated into
          # `public/virtual_worlds/zwift/` by `bin/rails virtual:world_images`
          # (see the README beside it), with the background colour of the
          # world's own map. The image rectangle is
          # the exact `zwift-data` bounds, so a recorded position lands where
          # the game drew it. The file name carries the digest of the pinned
          # source, so a new map always takes a new URL.
          key: "zwift",
          name: "Zwift",
          fit_fingerprints: [ { manufacturer: 144 }, { manufacturer: 260 } ],
          creator_aliases: %w[zwift],
          venues: [
            { key: "watopia", name: "Watopia", longitude: 166.95501, latitude: -11.68342, radius_m: 12_000,
              basemap: { image: "virtual_worlds/zwift/watopia-f4991742.webp", background: "#0884e2",
                         bounds: [ 166.87747, -11.74087, 167.03255, -11.62597 ] } },
            { key: "richmond", name: "Richmond", longitude: -77.44177, latitude: 37.5394, radius_m: 7_000,
              basemap: { image: "virtual_worlds/zwift/richmond-69e6f13f.webp", background: "#7c9938",
                         bounds: [ -77.48954, 37.5014, -77.394, 37.5774 ] } },
            { key: "london", name: "London", longitude: -0.11655, latitude: 51.49815, radius_m: 7_000,
              basemap: { image: "virtual_worlds/zwift/london-2fe1b8c8.webp", background: "#6f992d",
                         bounds: [ -0.1776, 51.4601, -0.0555, 51.5362 ] } },
            { key: "new_york", name: "New York", longitude: -73.97241, latitude: 40.702585, radius_m: 15_000,
              basemap: { image: "virtual_worlds/zwift/new_york-a93a82f7.webp", background: "#bbbbb7",
                         bounds: [ -74.022655, 40.587913, -73.922165, 40.817257 ] } },
            { key: "innsbruck", name: "Innsbruck", longitude: 11.41615, latitude: 47.2501, radius_m: 9_000,
              basemap: { image: "virtual_worlds/zwift/innsbruck-34f9344e.webp", background: "#7c9938",
                         bounds: [ 11.3501, 47.2055, 11.4822, 47.2947 ] } },
            { key: "bologna", name: "Bologna", longitude: 11.316267, latitude: 44.492721, radius_m: 8_000,
              basemap: { image: "virtual_worlds/zwift/bologna-8ac0c598.webp", background: "#b9b9b8",
                         bounds: [ 11.26261748, 44.45463821, 11.36991729102076, 44.5308037 ] } },
            { key: "yorkshire", name: "Yorkshire", longitude: -1.5671, latitude: 53.98725, radius_m: 7_000,
              basemap: { image: "virtual_worlds/zwift/yorkshire-6dad558c.webp", background: "#7c9938",
                         bounds: [ -1.632, 53.9491, -1.5022, 54.0254 ] } },
            { key: "crit_city", name: "Crit City", longitude: 165.80155, latitude: -10.38475, radius_m: 4_000,
              basemap: { image: "virtual_worlds/zwift/crit_city-973dcdcc.webp", background: "#7c9938",
                         bounds: [ 165.7824, -10.4038, 165.8207, -10.3657 ] } },
            { key: "makuri_islands", name: "Makuri Islands", longitude: 165.824065, latitude: -10.7949, radius_m: 11_000,
              basemap: { image: "virtual_worlds/zwift/makuri_islands-445cf44a.webp", background: "#7d9a35",
                         bounds: [ 165.76591, -10.85234, 165.88222, -10.73746 ] } },
            { key: "france", name: "France", longitude: 166.199825, latitude: -21.698975, radius_m: 11_000,
              basemap: { image: "virtual_worlds/zwift/france-c7bd7593.webp", background: "#6f992d",
                         bounds: [ 166.1384, -21.7564, 166.26125, -21.64155 ] } },
            { key: "paris", name: "Paris", longitude: 2.343175, latitude: 48.886709, radius_m: 8_000,
              basemap: { image: "virtual_worlds/zwift/paris-c5f46d67.webp", background: "#b9b9b9",
                         bounds: [ 2.285125, 48.848548, 2.401225, 48.924869 ] } },
            { key: "scotland", name: "Scotland", longitude: -5.22909, latitude: 55.6472, radius_m: 6_000,
              basemap: { image: "virtual_worlds/zwift/scotland-c35e210f.webp", background: "#aba73a",
                         bounds: [ -5.2802, 55.61845, -5.17798, 55.67595 ] } }
          ]
        }
      ].freeze

      module_function

      def all
        @all ||= ENTRIES.map { |entry| Platform.new(**entry) }.freeze
      end

      def fetch(key)
        key = key.to_s
        all.find { |platform| platform.key == key }
      end

      def for_creator(creator)
        return nil if creator.to_s.strip.empty?

        all.find { |platform| platform.matches_creator?(creator) }
      end

      def for_file_id(file_id)
        all.find { |platform| platform.matches_file_id?(file_id) }
      end

      # The device name a FIT fingerprint resolves to, or nil. The parser uses
      # it before the generic manufacturer/product fallbacks so a provider that
      # does not name itself still gets a creator.
      def creator_for(file_id) = for_file_id(file_id)&.name

      # The world map image of the world the point belongs to, or nil. A point
      # inside a world's image rectangle takes that world (the closest anchor
      # wins when rectangles overlap); a point just outside every rectangle but
      # inside a world's radius still takes that world, so a track that leaves
      # the published bounds draws on its world's map with the background
      # colour around it. A world the catalogue does not know, or one whose
      # image is not generated under `public_root`, keeps the ordinary basemap.
      def basemap_at(longitude:, latitude:, public_root:)
        venues = all.flat_map do |platform|
          platform.venues.filter_map do |venue|
            next unless venue.basemap
            next unless venue.basemap.available?(public_root)

            distance = venue.distance_to(longitude:, latitude:)
            [ venue, distance ] if distance <= venue.radius_m
          end
        end
        inside = venues.select { |venue, _| venue.basemap.contains?(longitude:, latitude:) }
        (inside.any? ? inside : venues).min_by(&:last)&.first&.basemap
      end

      # Token-normalised form shared by alias matching: case-insensitive,
      # every run of non-alphanumerics collapsed to one underscore.
      def normalize(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      end
    end
  end
end
