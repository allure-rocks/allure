# frozen_string_literal: true

module Allure
  module Gpx
    # Devices commonly write `<ele>0</ele>` as an "unknown" marker on a track
    # whose other points carry no elevation at all. In a recording segment
    # where at least one point has no valid elevation, every exact zero is such
    # a placeholder and becomes missing; a fully recorded segment keeps 0.0 as
    # a valid sea-level elevation. The parsers apply this to the recorded
    # profile, before any terrain override, so a DEM zero stays valid.
    module ElevationPlaceholders
      module_function

      def resolve(points)
        return points if points.all? { |point| Elevation.valid?(point.elevation) }
        return points unless points.any? { |point| point.elevation == 0.0 }

        points.map do |point|
          point.elevation == 0.0 ? point.with(elevation: nil) : point
        end
      end
    end
  end
end
