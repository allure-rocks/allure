# frozen_string_literal: true

class SegmentLeaderboardsController < ApplicationController
  before_action :set_segment

  def show
    raise ActiveRecord::RecordNotFound unless @segment.leaderboard_viewable_by?(current_user)

    @owner_view = @segment.user == current_user
    # The board this viewer reads: every athlete whose publication they may
    # read with the route shared, or only the accounts they follow
    # (docs/dev/SEGMENTS.md). The rendering decides names versus aliases.
    @board_scope = Segments::Listing::SCOPES.include?(params[:board]) ? params[:board] : "everyone"
    @sections = @segment.leaderboard_sections(viewer: current_user, scope: @board_scope)
    # The category view (docs/dev/SEGMENTS.md) filters each sport's ranking;
    # a section below the threshold renders nil and says so.
    @category = Segments::Categories.filter?(params[:category]) ? params[:category] : nil
    @offered_categories = Segments::Categories::FILTERS.select do |category|
      category == @category || @sections.any? { |_sport, efforts| Segments::Categories.offered?(efforts, category) }
    end
    @sections = @sections.map { |sport, efforts| [ sport, Segments::Categories.ranking(efforts, @category) ] } if @category
  end

  private

  def set_segment
    @segment = Segment.find_by_short_id!(params[:segment_id])
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
