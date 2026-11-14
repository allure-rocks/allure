# frozen_string_literal: true

module Segments
  # Runs recurring-route detection for one freshly imported recording
  # (PLAN_SEGMENTS.md §7.7). Serialized per account with the history sweep, so
  # two imports of the same circuit never create two suggestions.
  class SuggestRouteJob < ApplicationJob
    queue_as :default
    limits_concurrency key: ->(workout) { "route-suggestions-#{workout.user_id}" }, duration: 15.minutes

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(workout)
      Segments::RouteSuggestionDetector.call(workout)
    end
  end
end
