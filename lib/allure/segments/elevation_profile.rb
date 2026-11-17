# frozen_string_literal: true

module Allure
  module Segments
    # The course elevation profile: a bounded distance/elevation snapshot taken
    # once from the source recording and stored on the segment. Only the
    # terrain profile replaces it (docs/dev/ELEVATION.md); it never enters a
    # publication and never federates; a remote course has no profile and
    # reads as empty.
    class ElevationProfile
      MAX_POINTS = 240
      TABLE_ROWS = 30

      class << self
        # `points` are Allure::Segments::Point values from one contiguous
        # source slice. Returns [] when no numeric elevation exists, so the
        # stored value always distinguishes "built, no data" from "not built".
        def dump(points, max_points: MAX_POINTS)
          return [] if points.empty?

          base = points.first.distance
          raw = points.map do |point|
            { distance: (point.distance - base).round(1), elevation: point.elevation }
          end
          return [] unless raw.any? { |point| point[:elevation].is_a?(Numeric) }

          Allure::Gpx::ChartSeries.new(points: raw, series: [ :elevation ], max_points:).call.map do |point|
            { "d" => point[:distance], "ele" => point[:elevation] }
          end
        end

        # The endpoint payload: symbol-keyed points the chart controller reads.
        def points(segment)
          entries = segment.elevation_profile
          return [] unless entries.is_a?(Array)

          entries.filter_map do |entry|
            next unless entry.is_a?(Hash)

            distance = entry["d"]
            next unless distance.is_a?(Numeric)

            { distance:, elevation: entry["ele"].is_a?(Numeric) ? entry["ele"] : nil }
          end
        end

        # The text equivalent (DESIGN.md §15.1), sampled to a readable row
        # count without recomputing the profile.
        def table(segment, max_rows: TABLE_ROWS)
          rows = points(segment)
          return rows if max_rows <= 0 || rows.length <= max_rows

          step = (rows.length / max_rows.to_f).ceil
          rows.each_slice(step).map(&:first)
        end

        # The stored profile of the course run the other way: distances mirror
        # around the segment distance, so the entries stay ascending. [] and nil
        # pass through untouched.
        def reverse(profile, distance:)
          return profile unless profile.is_a?(Array) && profile.any?

          total = distance.to_f
          profile.reverse.map do |entry|
            next entry unless entry.is_a?(Hash) && entry["d"].is_a?(Numeric)

            entry.merge("d" => (total - entry["d"]).round(1))
          end
        end
      end
    end
  end
end
