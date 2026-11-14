# frozen_string_literal: true

module Segments
  # A route created from one of a pending suggestion's recordings accepts that
  # suggestion (PLAN_SEGMENTS.md §7.7): the banner closes, and the route keeps
  # the identity the owner chose. A route saved from the reference or from any
  # later repeat counts. A route saved from another recording leaves the
  # suggestion pending; its banner disappears once the reference carries the
  # route effort, and the owner can still dismiss it.
  class RouteSuggestionAcceptance
    def self.call(segment) = new(segment).call

    def initialize(segment)
      @segment = segment
    end

    def call
      return unless @segment.kind == "route" && @segment.source_workout_id

      RouteSuggestion.pending
        .where(user_id: @segment.user_id)
        .where(id: RouteSuggestionWorkout.where(workout_id: @segment.source_workout_id).select(:route_suggestion_id))
        .find_each { |suggestion| suggestion.update!(status: "accepted", segment: @segment) }
    end
  end
end
