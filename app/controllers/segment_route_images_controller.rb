# frozen_string_literal: true

# The owner route image of a course, served through the application like every
# other derived media: the visibility that admits the course admits its image
# (PLAN_SEGMENTS.md §8.1), and no viewer ever receives a raw storage URL. The
# image is rendered from the segment's own geometry, never from the source
# workout's track.
class SegmentRouteImagesController < ApplicationController
  before_action :set_viewable_segment

  def show
    attachment = @segment.route_image_variant(params[:theme])
    raise ActiveRecord::RecordNotFound unless attachment

    response.headers["Cache-Control"] = "private, no-store"
    send_data attachment.download,
              filename: attachment.filename.to_s,
              type: "image/png",
              disposition: "inline"
  end

  private

  # Any denial surfaces as 404, never 403, matching the segment track endpoint
  # and the M1 convention.
  def set_viewable_segment
    @segment = Segment.find_by_short_id!(params[:segment_id])
    raise ActiveRecord::RecordNotFound unless @segment.viewable_by?(current_user)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
