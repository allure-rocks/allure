# frozen_string_literal: true

# Owner-only elevation source switch (docs/dev/ELEVATION.md). The request is
# recorded as a pending preference and the actual reanalysis runs in a job, so
# the page never blocks on the provider.
class WorkoutElevationSourcesController < ApplicationController
  before_action :set_owned_workout

  def update
    source = params[:elevation_source].to_s
    return head :unprocessable_content unless Workout::ELEVATION_SOURCES.include?(source)
    return head :unprocessable_content unless enabled?

    @workout.update!(elevation_source_requested: source)
    Workouts::ApplyElevationSourceJob.perform_later(@workout, source)
    redirect_to workout_path(@workout, anchor: "section-profile"), notice: t("workouts.elevation.switch_notice")
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_content
  rescue StandardError => error
    # A queue outage must not leave a request pending forever: the switch
    # button for the requested source is disabled while the request stands.
    @workout.update!(elevation_source_requested: nil)
    Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: @workout.id })
    redirect_to workout_path(@workout, anchor: "section-profile"), alert: t("workouts.elevation.switch_failed")
  end

  private

  def enabled?
    Allure::Elevation::Config.configured? && current_user.elevation_enrichment_enabled?
  end

  def set_owned_workout
    @workout = current_user.workouts.positioned.find_by_short_id!(params[:workout_id])
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
