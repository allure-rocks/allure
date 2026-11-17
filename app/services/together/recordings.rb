# frozen_string_literal: true

module Together
  # A workout as the co-presence detector reads it (docs/dev/SHARED-ACTIVITIES.md): its
  # stored points in time order and the facts that gate a match. Shared by
  # detection, the credit-to-link suggestion and the backfill.
  module Recordings
    module_function

    def for(workout)
      points = Allure::Segments::PointStream.new(
        segments: workout.track_segments,
        workout_started_at: workout.started_at
      ).call
      Allure::Together::Detector::Recording.new(
        sport_slug: workout.sport.slug,
        virtual: workout.sport.virtual,
        commute: workout.commute,
        moving_time: workout.moving_time,
        points:
      )
    end
  end
end
