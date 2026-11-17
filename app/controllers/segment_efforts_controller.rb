# frozen_string_literal: true

# The viewer's own efforts on a segment. Other athletes' efforts never appear
# here: the shared board is the only cross-athlete surface, and it lists
# participants only (docs/dev/SEGMENTS.md). Denial is 404, never 403.
class SegmentEffortsController < ApplicationController
  before_action :set_segment

  def index
    raise ActiveRecord::RecordNotFound unless @segment.viewable_by?(current_user)

    @efforts = @segment.segment_efforts
      .where(user: current_user)
      .includes(:workout)
      .order(:elapsed_time, :started_at, :id)
  end

  private

  def set_segment
    @segment = Segment.find_by_short_id!(params[:segment_id])
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
