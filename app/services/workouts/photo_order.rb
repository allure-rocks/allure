# frozen_string_literal: true

module Workouts
  # The gallery's order (PLAN_PHOTOS.md §2.1): capture time first, then the
  # route position of a photo that recorded no time, then the upload order.
  # The owner takes over by reordering by hand; « Trier par heure de prise de
  # vue » resumes the automatic order.
  class PhotoOrder
    def initialize(workout:)
      @workout = workout
    end

    def apply
      @workout.with_lock do
        reorder unless @workout.photos_ordered_by_owner?
      end
    end

    def resume_automatic!
      @workout.with_lock do
        @workout.update!(photos_ordered_by_owner: false)
        reorder
      end
    end

    private

    def reorder
      photos = @workout.photos.to_a
      return if photos.size < 2

      placement = PhotoPlacement.new(workout: @workout)
      ordered = photos.sort_by do |photo|
        instant = placement.capture_time(photo) ||
                  (photo.track_elapsed && @workout.started_at + photo.track_elapsed)
        # The upload order is the creation order, never the current positions:
        # resuming the automatic order after a manual one must be able to
        # restore it.
        [ instant ? 0 : 1, instant.to_f, photo.id ]
      end
      ordered.each_with_index do |photo, index|
        photo.update!(position: index) unless photo.position == index
      end
    end
  end
end
