# frozen_string_literal: true

class RemoteNoteChartsController < ApplicationController
  def show
    note = RemoteNote.find(params[:id])
    policy = Federation::RemoteNotePolicy.new(
      note:, principal: Workouts::PublicationPrincipal.browser(current_user)
    )
    raise ActiveRecord::RecordNotFound unless policy.allowed?(resource: :chart)

    response.headers["Cache-Control"] = "private, no-store"
    render json: { points: note.representation["chart"] }
  rescue ActiveRecord::RecordNotFound, ArgumentError
    head :not_found
  end
end
