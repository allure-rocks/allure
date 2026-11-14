# frozen_string_literal: true

# Copies another account's shared course into the current account's private
# segments, in the recorded direction or reversed, and creates the reversed
# copy of the owner's own segment or route. The copy is a new course; nothing
# about the source is mutated, and its board is never touched.
class SegmentCopiesController < ApplicationController
  DIRECTIONS = %w[forward reverse].freeze

  before_action :set_source_segment
  before_action :ensure_owner_direction

  def create
    direction = params[:direction].to_s
    raise ActiveRecord::RecordNotFound unless DIRECTIONS.include?(direction)

    result = Segments::LocalCopier.new(
      user: current_user,
      segment: @segment,
      reversed: direction == "reverse"
    ).call!
    redirect_to segment_path(result.segment), notice: t(notice_key(direction))
  rescue Segments::LocalCopier::CopyError => error
    redirect_to segment_path(@segment), alert: error.message
  end

  private

  # Any readable shared course can be copied; a private one is only readable
  # by its owner, whom the next guard restricts to the reversed direction.
  # Every denial is a 404.
  def set_source_segment
    @segment = Segment.find_by_short_id!(params[:segment_id])
    raise ActiveRecord::RecordNotFound unless @segment.viewable_by?(current_user)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  # The forward copy is for another account's shared course; the owner only
  # creates the reversed copy of their own segment or route (a loop is already
  # its own circuit).
  def ensure_owner_direction
    return unless @segment.user == current_user

    raise ActiveRecord::RecordNotFound unless params[:direction].to_s == "reverse"
  end

  def notice_key(direction)
    direction == "reverse" ? "segments.copy.reverse_success" : "segments.copy.success"
  end
end
