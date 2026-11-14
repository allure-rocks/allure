# frozen_string_literal: true

module Workouts
  # Re-renders every owner route image whose stored renderer generation is
  # older than the current one, or that was reset to 0 when a re-analysis
  # replaced the geometry (PLAN_DERIVATIONS.md §4). Bounded id-cursor batches
  # that resume themselves on the low-concurrency `route_images` worker.
  # Publication images are snapshot media and are deliberately out of scope.
  class BackfillRouteImagesJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    class << self
      # A credit row and a positionless recording have no track to draw
      # (PLAN_TOGETHER.md §6.6, PLAN_NO_GPS.md §6).
      def pending_scope
        Workout.positioned.where(route_image_version: ...RouteImage::VERSION)
      end
    end

    def perform(after_id: 0)
      workouts = self.class.pending_scope
        .where("workouts.id > ?", after_id)
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a

      workouts.each { |workout| RenderRouteImageJob.perform_later(workout) }

      self.class.perform_later(after_id: workouts.last.id) if workouts.length == BATCH_SIZE
    end
  end
end
