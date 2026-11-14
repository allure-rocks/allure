# frozen_string_literal: true

# Owner-only place-name suggestions for the workout list's autocomplete
# (DESIGN.md §13). Names only, bounded, and never cached.
class WorkoutPlaceSuggestionsController < ApplicationController
  def index
    names = Workouts::PlaceSuggestions.new(user: current_user, query: params[:q]).call

    response.headers["Cache-Control"] = "private, no-store"
    render json: { places: names }
  end
end
