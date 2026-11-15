# frozen_string_literal: true

# Reads the owner's stored toponymy. The page never schedules geocoding: the
# import, the re-analysis, the sweeps and the recovery job do
# (PLAN_DERIVATIONS.md §4), so this endpoint has no side effect.
class WorkoutToponymiesController < ApplicationController
  def show
    workout = current_user.workouts.positioned.find_by_short_id!(params[:workout_id])
    response.headers["Cache-Control"] = "private, no-store"

    # A virtual workout is never geocoded; its place comes from the platform's
    # venue catalog (docs/dev/VIRTUAL-PLATFORMS.md).
    toponymy = workout.toponymy unless workout.sport.virtual?
    return render json: { status: "unavailable" } unless toponymy

    render json: payload(toponymy, workout:)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  private

  def payload(toponymy, workout:)
    result = { status: toponymy.status }
    return result unless toponymy.ready? || toponymy.partial?

    start = public_place(toponymy.start_place)
    finish = public_place(toponymy.finish_place)
    result.merge(
      start:,
      finish:,
      loop: loop_route?(workout),
      markers: Array(toponymy.markers).filter_map { public_marker(it) }
    )
  end

  def loop_route?(workout)
    Workouts::LoopRoute.new(workout:).call
  end

  def public_place(place)
    place.to_h.slice("name", "kind")
  end

  def public_marker(marker)
    value = marker.to_h.slice("distance", "elevation", "name", "kind", "rank")
    return if value["distance"].nil? || value["name"].blank?

    value
  end
end
