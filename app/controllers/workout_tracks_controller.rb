# frozen_string_literal: true

class WorkoutTracksController < ApplicationController
  # Owner requests read the point rows; non-owner requests use the immutable
  # publication representation and never fall back to the source track.
  # `?as=publication` forces the sanitized publication track even for the owner,
  # so the sharing snapshot can show exactly what non-owners see (docs/dev/PUBLISHING.md
  # Slice 7). It still requires publication policy for :track and 404s otherwise.
  # A reader gets the track of the publication serving them, and the owner's
  # preview the one of `audience` (docs/dev/PUBLISHING.md).
  def show
    workout = Workout.find_by_short_id!(params[:workout_id])
    if params[:as] == "publication"
      publication = Workouts::PublicationResolver.new(workout:, user: current_user, audience: params[:audience]).call
      policy = Workouts::PublicationPolicy.new(
        publication:,
        principal: Workouts::PublicationPrincipal.browser(current_user)
      )
      raise ActiveRecord::RecordNotFound unless policy.allowed?(resource: :track)

      track = publication.track
    elsif workout.user == current_user
      # A positionless recording has no track at all (PLAN_NO_GPS.md §6).
      raise ActiveRecord::RecordNotFound unless workout.positioned?

      track = Allure::Gpx::TrackSeries.new(segments: workout.track_segments).call
    else
      publication = Workouts::PublicationResolver.new(workout:, user: current_user).call
      policy = Workouts::PublicationPolicy.new(
        publication:,
        principal: Workouts::PublicationPrincipal.browser(current_user)
      )
      raise ActiveRecord::RecordNotFound unless policy.allowed?(resource: :track)

      track = publication.track
    end

    response.headers["Cache-Control"] = "private, no-store"
    render json: track, content_type: "application/geo+json"
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
