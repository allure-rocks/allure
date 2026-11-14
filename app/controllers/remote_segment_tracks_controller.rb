# frozen_string_literal: true

class RemoteSegmentTracksController < ApplicationController
  def show
    segment = RemoteSegment.find(params[:id])
    policy = Federation::RemoteSegmentPolicy.new(
      segment:, principal: Workouts::PublicationPrincipal.browser(current_user)
    )
    raise ActiveRecord::RecordNotFound unless policy.allowed?(resource: :track)

    response.headers["Cache-Control"] = "private, no-store"
    render json: segment.representation["track"], content_type: "application/geo+json"
  rescue ActiveRecord::RecordNotFound, ArgumentError
    head :not_found
  end
end
