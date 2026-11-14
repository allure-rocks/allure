# frozen_string_literal: true

module Allure
  module Elevation
    # Workout-wide horizontal cumulative distance over ordered track segments.
    #
    # Segments are chained in document order: the straight-line horizontal
    # distance between the last point of one segment and the first point of the
    # next continues the axis, so a recording gap never resets it. Sampling and
    # interpolation both read this series, which keeps their distances aligned.
    module TrackGeometry
      module_function

      # Returns one entry per segment: an array of cumulative distances in
      # metres, aligned with that segment's points.
      def cumulative_distances(segments)
        offset = 0.0
        previous = nil

        segments.map do |segment|
          points = segment.points
          next [] if points.empty?

          offset += gap_distance(previous, points.first) if previous
          distances = [ offset ]
          points.each_cons(2) do |point, next_point|
            distances << distances.last + Allure::Gpx::Geo.horizontal_distance(
              point.latitude, point.longitude,
              next_point.latitude, next_point.longitude
            )
          end
          offset = distances.last
          previous = points.last
          distances
        end
      end

      def gap_distance(previous, current)
        Allure::Gpx::Geo.horizontal_distance(
          previous.latitude, previous.longitude,
          current.latitude, current.longitude
        )
      end
    end
  end
end
