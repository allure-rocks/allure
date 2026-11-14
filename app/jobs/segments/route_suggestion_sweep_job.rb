# frozen_string_literal: true

module Segments
  # Walks one account's positioned recordings from the newest to the oldest and
  # runs recurring-route detection on each (PLAN_SEGMENTS.md §7.7). The order
  # matters: the first occurrence of a circuit the walk reaches is the newest
  # one, so the suggestion's reference workout — the geometry the route form
  # uses — is the most recent recording. Resumable through the (started_at, id)
  # keyset, and serialized per account with the live detection job.
  class RouteSuggestionSweepJob < ApplicationJob
    BATCH_SIZE = 25

    queue_as :default
    limits_concurrency key: ->(user_id, **) { "route-suggestions-#{user_id}" }, duration: 30.minutes

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    # The recordings the current detector has not examined yet.
    def self.pending_scope
      Workout.positioned.where(route_suggestion_version: ...RouteSuggestionDetector::VERSION)
    end

    # One sweep per concerned account; the sweep itself walks newest first.
    def self.enqueue_all
      pending_scope.distinct.pluck(:user_id).each { |user_id| perform_later(user_id) }
    end

    def perform(user_id, cursor_started_at: nil, cursor_id: nil)
      user = User.find_by(id: user_id)
      return if user.nil? || user.deactivated?

      scope = self.class.pending_scope.where(user_id: user.id)
      if cursor_started_at
        scope = scope.where(
          "(workouts.started_at, workouts.id) < (?, ?)",
          Time.zone.parse(cursor_started_at.to_s),
          cursor_id
        )
      end
      workouts = scope.order(started_at: :desc, id: :desc).limit(BATCH_SIZE).to_a
      workouts.each { |workout| RouteSuggestionDetector.call(workout) }

      return unless workouts.length == BATCH_SIZE

      last = workouts.last
      self.class.perform_later(user_id, cursor_started_at: last.started_at.iso8601, cursor_id: last.id)
    end
  end
end
