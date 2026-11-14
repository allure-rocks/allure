# frozen_string_literal: true

module Workouts
  # Re-places a workout's automatically placed photos after its recording or
  # its camera-clock correction changed (PLAN_PHOTOS.md §4).
  class PhotoPlacementJob < ApplicationJob
    queue_as :photos
    discard_on ActiveJob::DeserializationError

    def perform(workout)
      PhotoPlacement.new(workout:).refresh_all
      PhotoOrder.new(workout:).apply
    end
  end
end
