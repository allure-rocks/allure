# frozen_string_literal: true

class RoutesController < ApplicationController
  before_action :set_source_workout

  def new
    @route_suggestion = suggested_route_suggestion
    @route = current_user.segments.new(
      kind: "route",
      visibility: "private",
      match_tolerance_meters: Segments::Creator::ROUTE_MATCH_TOLERANCE_METERS,
      source_workout: @workout,
      name: (@route_suggestion ? Segments::RouteSuggestionName.call(@route_suggestion) : nil)
    )
  end

  def create
    @route = Segments::Creator.new(
      user: current_user,
      workout: @workout,
      kind: "route",
      name: route_params[:name],
      description: route_params[:description],
      match_tolerance_meters: route_params[:match_tolerance_meters]
    ).call

    if @route.persisted?
      # Saving the route from one of a suggestion's recordings accepts it
      # (PLAN_SEGMENTS.md §7.7): the banner closes and the route keeps the
      # identity the owner chose.
      Segments::RouteSuggestionAcceptance.call(@route)
      redirect_to segment_path(@route), notice: t("routes.create.success")
    else
      @route_suggestion = suggested_route_suggestion
      render :new, status: :unprocessable_content
    end
  end

  private

  def set_source_workout
    @workout = current_user.workouts.positioned.find_by_short_id!(params[:workout_id])
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  # The suggestion the owner came from, only while it is pending and only when
  # the source workout is one of its recordings. An unknown or foreign id is
  # ignored, never resolved.
  def suggested_route_suggestion
    id = params[:route_suggestion].to_s.presence
    return unless id

    suggestion = current_user.route_suggestions.pending.find_by(id: id)
    return unless suggestion
    return unless suggestion.route_suggestion_workouts.exists?(workout_id: @workout.id)

    suggestion
  end

  def route_params
    params.fetch(:route, {}).permit(:name, :description, :match_tolerance_meters)
  end
end
