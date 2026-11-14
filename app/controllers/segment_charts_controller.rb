# frozen_string_literal: true

class SegmentChartsController < ApplicationController
  before_action :set_viewable_segment

  def show
    response.headers["Cache-Control"] = "private, no-store"
    render json: { points: Allure::Segments::ElevationProfile.points(@segment) }
  end

  private

  # The course profile follows the segment's own visibility, like its track.
  def set_viewable_segment
    @segment = Segment.find_by_short_id!(params[:segment_id])
    raise ActiveRecord::RecordNotFound unless @segment.viewable_by?(current_user)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
