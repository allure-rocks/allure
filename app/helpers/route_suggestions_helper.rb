# frozen_string_literal: true

module RouteSuggestionsHelper
  # The pending suggestions naming this recording (PLAN_SEGMENTS.md §7.7),
  # owner-only: the banner is rendered on the owner's page only. A suggestion
  # whose reference already carries a route effort is left out — the owner
  # saved the route from another recording, and the banner has nothing left to
  # offer.
  def open_route_suggestions_for(workout)
    RouteSuggestion.pending
      .where(id: RouteSuggestionWorkout.where(workout_id: workout.id).select(:route_suggestion_id))
      .where(
        "route_suggestions.reference_workout_id IS NULL OR route_suggestions.reference_workout_id NOT IN (?)",
        SegmentEffort.joins(:segment).where(segments: { kind: "route" }).select(:workout_id)
      )
      .order(:id)
  end
end
