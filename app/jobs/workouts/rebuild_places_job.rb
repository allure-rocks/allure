# frozen_string_literal: true

module Workouts
  # Reassembles one workout's stored place list from its existing toponymy.
  # Pure and offline; the backfill only enqueues it for rows whose list is
  # stale.
  class RebuildPlacesJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
              ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(workout)
      PlaceNamer.new(workout:).call
    rescue StandardError => error
      Rails.error.report(error, handled: false, context: { component: self.class.name, workout_id: workout.id })
      raise
    end
  end
end
