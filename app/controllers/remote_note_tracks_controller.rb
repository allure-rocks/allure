# frozen_string_literal: true

# Serves the parsed remote track exactly like a local publication track:
# policy-gated, private, and never built from source-workout data.
class RemoteNoteTracksController < ApplicationController
  def show
    note = RemoteNote.find(params[:id])
    policy = Federation::RemoteNotePolicy.new(
      note:, principal: Workouts::PublicationPrincipal.browser(current_user)
    )
    raise ActiveRecord::RecordNotFound unless policy.allowed?(resource: :track)

    response.headers["Cache-Control"] = "private, no-store"
    render json: note.representation["track"], content_type: "application/geo+json"
  rescue ActiveRecord::RecordNotFound, ArgumentError
    head :not_found
  end
end
