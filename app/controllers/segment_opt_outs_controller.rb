# frozen_string_literal: true

# Opt-out leaderboard participation (docs/dev/SEGMENTS.md): every matched
# athlete is ranked by default; a row excludes the athlete and destroying it
# removes the exclusion. There is no effort requirement — excluding a course
# before running it is allowed — and the owner is not a special case. Denial is
# 404, never 403.
class SegmentOptOutsController < ApplicationController
  before_action :set_segment
  before_action :require_shared_segment

  def create
    @segment.segment_opt_outs.find_or_create_by!(user: current_user)
    redirect_to segment_path(@segment), notice: t("segments.listing.create.success")
  rescue ActiveRecord::RecordNotUnique
    # A concurrent exclusion won the unique index; the athlete is excluded.
    redirect_to segment_path(@segment), notice: t("segments.listing.create.success")
  end

  def destroy
    @segment.segment_opt_outs.find_by(user: current_user)&.destroy!
    redirect_to segment_path(@segment), notice: t("segments.listing.destroy.success")
  end

  private

  def set_segment
    @segment = Segment.find_by_short_id!(params[:segment_id])
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  # A private route or loop has no board, so there is nothing to opt out of.
  def require_shared_segment
    raise ActiveRecord::RecordNotFound unless @segment.shareable? && @segment.viewable_by?(current_user)
  end
end
