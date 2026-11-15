# frozen_string_literal: true

module Allure
  module Virtual
    # The published map image of a virtual world (docs/dev/VIRTUAL-PLATFORMS.md). A world's
    # recorded positions are fictional, so the ordinary basemap draws them over
    # open sea or over a real city that only roughly matches; this image is the
    # world as its own game renders it.
    #
    # `bounds` is [west, south, east, north] and comes from the MIT-licensed
    # `zwift-data` package (andipaetzold/zwift-data, `src/worlds.ts`), which is
    # the same source the venue anchors use; Paris's July 2026 map is the one
    # exception, registered against the previous rectangle because zwift-data
    # does not publish it yet (docs/dev/VIRTUAL-PLATFORMS.md). `background` fills the
    # viewport around the image (the world's own sea or sky colour), and
    # `attribution` is the credit the map control shows.
    Basemap = Data.define(:image, :bounds, :background, :attribution) do
      COLOUR_PATTERN = /\A#[0-9a-f]{6}\z/i
      # The dark surface keeps the world's hue but dims it under the dark PNG
      # (DESIGN.md §15.4), the same way the raster basemap is never composited
      # into a dark render.
      DARK_FACTOR = 0.32

      def initialize(image:, bounds:, background:, attribution: "© Zwift")
        west, south, east, north = Array(bounds).map { |value| Float(value) }
        unless west < east && south < north
          raise ArgumentError, "invalid virtual world bounds"
        end
        unless COLOUR_PATTERN.match?(background.to_s)
          raise ArgumentError, "invalid virtual world background"
        end

        super(
          image: image.to_s.freeze,
          bounds: [ west, south, east, north ].freeze,
          background: background.to_s.freeze,
          attribution: attribution.to_s.freeze
        )
      end

      def west = bounds[0]
      def south = bounds[1]
      def east = bounds[2]
      def north = bounds[3]

      def contains?(longitude:, latitude:)
        longitude.to_f.between?(west, east) && latitude.to_f.between?(south, north)
      end

      # MapLibre's image-source corner order: top-left, top-right, bottom-right,
      # bottom-left, as [longitude, latitude] pairs.
      def coordinates
        [ [ west, north ], [ east, north ], [ east, south ], [ west, south ] ]
      end

      # The public path the browser fetches. The file is generated into
      # `public/` by `bin/rails virtual:world_images`, so no asset pipeline
      # step and no third-party origin is involved.
      def path = "/#{image}"

      # The image is optional: Zwift's artwork is not ours to redistribute, so
      # it is not committed (public/virtual_worlds/zwift/README.md). An
      # operator who generated it with `bin/rails virtual:world_images` gets
      # the world map; a checkout without it draws the ordinary basemap.
      def available?(public_root)
        File.file?(File.join(public_root.to_s, image))
      end

      def dark_background
        red, green, blue = background.delete_prefix("#").scan(/../).map { |channel| (channel.to_i(16) * DARK_FACTOR).round }
        format("#%02x%02x%02x", red, green, blue)
      end

      # What the map element hands the Stimulus controller, and what the route
      # image renderer serialises into its payload. The dark background is the
      # same colour dimmed, so the area around the image follows the dark theme
      # instead of staying the world's bright sea colour.
      def to_map
        { image: path, coordinates:, background:, darkBackground: dark_background, attribution: }
      end
    end
  end
end
