# frozen_string_literal: true

module Allure
  module Segments
    # The segment index's course glyph (DESIGN.md §20.6): SVG path data of the
    # course line, fitted into a square box with its aspect ratio kept. Input
    # is `[longitude, latitude]` pairs (GeoJSON order), already simplified by
    # the caller; longitudes are scaled by cos(latitude) so a course keeps its
    # real shape. Purely decorative: no coordinate leaves in the output beyond
    # the box-relative shape.
    class Thumbnail
      def initialize(coordinates, size:, padding: 2.0)
        @coordinates = coordinates
        @size = size.to_f
        @padding = padding.to_f
      end

      def call
        points = projected
        return nil if points.length < 2

        xs = points.map(&:first)
        ys = points.map(&:last)
        min_x, max_x = xs.minmax
        min_y, max_y = ys.minmax
        extent = [ max_x - min_x, max_y - min_y ].max
        return nil unless extent.positive?

        inner = @size - (2 * @padding)
        scale = inner / extent
        offset_x = @padding + ((inner - ((max_x - min_x) * scale)) / 2.0)
        offset_y = @padding + ((inner - ((max_y - min_y) * scale)) / 2.0)

        coordinates = points.map do |x, y|
          [ (offset_x + ((x - min_x) * scale)).round(1), (offset_y + ((max_y - y) * scale)).round(1) ]
        end
        "M" + coordinates.map { |x, y| "#{x} #{y}" }.join(" L")
      end

      private

      def projected
        pairs = Array(@coordinates).filter_map do |pair|
          next unless pair.is_a?(Array) && pair.length >= 2

          longitude, latitude = pair
          next unless longitude.is_a?(Numeric) && latitude.is_a?(Numeric)

          [ longitude.to_f, latitude.to_f ]
        end
        return [] if pairs.empty?

        mean_latitude = pairs.sum(&:last) / pairs.length
        factor = Math.cos(mean_latitude * Math::PI / 180.0)
        pairs.map { |longitude, latitude| [ longitude * factor, latitude ] }
      end
    end
  end
end
