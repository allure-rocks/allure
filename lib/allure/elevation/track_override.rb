# frozen_string_literal: true

module Allure
  module Elevation
    # Replaces every track point's elevation with the profile value at its
    # workout-wide cumulative distance. Points the profile cannot cover keep no
    # elevation. The source track and its points are never mutated; unchanged
    # points are reused.
    module TrackOverride
      module_function

      def call(track, profile:)
        distances = TrackGeometry.cumulative_distances(track.segments)
        segments = track.segments.each_with_index.map do |segment, segment_index|
          points = segment.points.each_with_index.map do |point, point_index|
            elevation = profile.elevation_at(distances[segment_index][point_index])
            next point if point.elevation == elevation

            point.with(elevation:)
          end
          Allure::Gpx::Segment.new(points:)
        end

        Allure::Gpx::Track.new(
          creator: track.creator,
          name: track.name,
          description: track.description,
          calories: track.calories,
          source_max_speed: track.source_max_speed,
          source_ascent: track.source_ascent,
          source_descent: track.source_descent,
          activity_signals: track.activity_signals,
          segments:,
          laps: track.laps
        )
      end
    end
  end
end
