# frozen_string_literal: true

# The first step of creating a segment or a route from the segment index
# (DESIGN.md §20.6): the owner picks the source activity among their own
# positioned recordings, then selects the portion on that workout's creation
# page. The most recent activity leads as a shortcut and is left out of the
# list below while no place filter is set.
class SegmentSourcesController < ApplicationController
  include Pagy::Method

  KINDS = %w[segment route].freeze

  helper_method :source_kind, :source_place, :source_creation_path

  def new
    scope = current_user.workouts.positioned
    @any_source = scope.exists?
    @latest = source_place.blank? ? scope.order(started_at: :desc, id: :desc).first : nil

    listed = Workouts::ListQuery.new(user: current_user, params: { place: source_place }.compact_blank)
      .resolve(scope: scope.with_attached_route_image.includes(:sport))
      .reorder(started_at: :desc, id: :desc)
    listed = listed.where.not(id: @latest.id) if @latest
    @pagy, @workouts = pagy(listed, limit: 20)
  end

  private

  def source_kind = KINDS.include?(params[:kind]) ? params[:kind] : "segment"

  def source_place = params[:place].to_s.strip.truncate(120)

  def source_creation_path(workout)
    source_kind == "route" ? new_workout_route_path(workout) : new_workout_segment_path(workout)
  end
end
