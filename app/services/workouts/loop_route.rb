# frozen_string_literal: true

module Workouts
  # The display-only loop rule: a route whose first and last source points sit
  # within 250 m describes a closed loop and presents one combined
  # `Départ et arrivée` endpoint. Separate from the 30 m loop-segment detector
  # (Allure::Geometry::LoopDetector), exactly as docs/dev/WORKOUT.md states.
  class LoopRoute
    RADIUS_METRES = 250.0

    def initialize(workout:)
      @workout = workout
    end

    def call
      segments = @workout.track_segments.to_a
      coordinates = [ segments.first&.points&.first, segments.last&.points&.last ].map do |point|
        [ point&.fetch("lat", nil), point&.fetch("lon", nil) ]
      end
      return false unless coordinates.flatten.all? { |value| value.is_a?(Numeric) && value.finite? }

      Allure::Gpx::Geo.horizontal_distance(*coordinates[0], *coordinates[1]) <= RADIUS_METRES
    end
  end
end
