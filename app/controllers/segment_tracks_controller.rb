# frozen_string_literal: true

class SegmentTracksController < ApplicationController
  before_action :set_viewable_segment

  def show
    # Same FeatureCollection shape as a workout track so one map controller
    # reads both, with the cumulative distances the profile hover sync needs
    # and no per-point metrics to colour a track by.
    track = Allure::Segments::TrackSeries.new(
      coordinates: @segment.geom.points.map { [ it.x, it.y ] },
      distance: @segment.distance
    ).call

    response.headers["Cache-Control"] = "private, no-store"
    render json: track, content_type: "application/geo+json"
  end

  private

  # Geometry only follows the segment's own visibility; the board audience is a
  # separate gate (Segment#viewable_by?).
  def set_viewable_segment
    @segment = Segment.find_by_short_id!(params[:segment_id])
    raise ActiveRecord::RecordNotFound unless @segment.viewable_by?(current_user)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
