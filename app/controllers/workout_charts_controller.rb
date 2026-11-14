# frozen_string_literal: true

class WorkoutChartsController < ApplicationController
  def show
    workout = Workout.find_by_short_id!(params[:workout_id])
    # `?as=publication` serves the owner the publication chart, as for the
    # track, so the reader preview never shows unpublished data. A reader gets
    # the chart of the publication serving them (PLAN_AUDIENCES.md §3).
    if workout.user != current_user || params[:as] == "publication"
      audience = params[:audience] if params[:as] == "publication"
      publication = Workouts::PublicationResolver.new(workout:, user: current_user, audience:).call
      policy = Workouts::PublicationPolicy.new(
        publication:,
        principal: Workouts::PublicationPrincipal.browser(current_user)
      )
      raise ActiveRecord::RecordNotFound unless policy.allowed?(resource: :chart)

      points = publication.representation["chart"]

      response.headers["Cache-Control"] = "private, no-store"
      render json: { points: }
      return
    end

    extended = params[:version] == "2"
    points = Allure::Gpx::ChartSeries.new(
      workout_started_at: workout.started_at,
      segments: workout.track_segments,
      series: extended ? Allure::Gpx::ChartSeries::SERIES_KEYS.keys : [ :elevation ],
      extra_values: (Workouts::WeatherChartValues.call(workout) if extended)
    ).call

    response.headers["Cache-Control"] = "private, no-store"
    if extended
      available_series = (Allure::Gpx::ChartSeries::SERIES_KEYS.keys + Workouts::WeatherChartValues::KEYS).select do |key|
        points.any? { |point| !point[key].nil? }
      end
      render json: { version: 2, available_series:, points: }
    else
      render json: { points: }
    end
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
