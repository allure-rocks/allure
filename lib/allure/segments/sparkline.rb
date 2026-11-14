# frozen_string_literal: true

module Allure
  module Segments
    # The segment index's mini elevation profile (DESIGN.md §20.6): SVG path
    # data for a line and its filled area, drawn from the stored course
    # profile (`{ "d" =>, "ele" => }` entries) into a fixed box. Elevation
    # gaps are skipped, not bridged with zeros; a profile with fewer than two
    # elevations has no sparkline.
    class Sparkline
      Result = Data.define(:line, :area, :min_elevation, :max_elevation)

      # A flat course would otherwise draw on the box floor: the vertical scale
      # never stretches less than this many metres over the box height.
      MIN_RANGE_METRES = 20.0

      def initialize(profile, width:, height:, padding: 1.0)
        @profile = profile
        @width = width.to_f
        @height = height.to_f
        @padding = padding.to_f
      end

      def call
        points = samples
        return nil if points.length < 2

        distances = points.map(&:first)
        elevations = points.map(&:last)
        min_distance, max_distance = distances.minmax
        span = max_distance - min_distance
        return nil unless span.positive?

        min_elevation, max_elevation = elevations.minmax
        range = [ max_elevation - min_elevation, MIN_RANGE_METRES ].max
        floor = min_elevation - ((range - (max_elevation - min_elevation)) / 2.0)
        inner_width = @width - (2 * @padding)
        inner_height = @height - (2 * @padding)

        coordinates = points.map do |distance, elevation|
          x = @padding + (((distance - min_distance) / span) * inner_width)
          y = @padding + inner_height - (((elevation - floor) / range) * inner_height)
          [ x.round(1), y.round(1) ]
        end

        line = "M" + coordinates.map { |x, y| "#{x} #{y}" }.join(" L")
        bottom = (@height - @padding).round(1)
        area = "#{line} L#{coordinates.last.first} #{bottom} L#{coordinates.first.first} #{bottom} Z"
        Result.new(line:, area:, min_elevation:, max_elevation:)
      end

      private

      def samples
        return [] unless @profile.is_a?(Array)

        @profile.filter_map do |entry|
          next unless entry.is_a?(Hash)

          distance = entry["d"] || entry[:d]
          elevation = entry["ele"] || entry[:ele]
          next unless distance.is_a?(Numeric) && elevation.is_a?(Numeric)
          next unless distance.to_f.finite? && elevation.to_f.finite?

          [ distance.to_f, elevation.to_f ]
        end
      end
    end
  end
end
