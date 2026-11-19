# frozen_string_literal: true

# The owner's assistant summary (docs/dev/AI.md §7): request or regenerate it,
# and accept the proposed title. Every action is scoped to the account's own
# workouts; a reader never reaches this controller.
class WorkoutSummariesController < ApplicationController
  THROTTLE = 5.minutes

  before_action :set_owned_workout

  def create
    unless Workouts::SummaryEligibility.eligible?(@workout)
      return redirect_to(workout_path(@workout), notice: t("workouts.summary.unavailable"))
    end
    if throttled?
      return redirect_to(workout_path(@workout), notice: t("workouts.summary.throttled"))
    end

    Workouts::SummaryRefresh.schedule(@workout, explicit: true)
    redirect_to workout_path(@workout), notice: t("workouts.summary.requested")
  end

  def apply_title
    summary = @workout.assistant_summary
    unless summary&.ready? && summary.title.present?
      return redirect_to(workout_path(@workout), notice: t("workouts.summary.unavailable"))
    end

    @workout.update!(title: summary.title, title_source: "owner")
    redirect_to workout_path(@workout), notice: t("workouts.summary.title_applied")
  end

  private

  def throttled?
    row = @workout.assistant_summary
    row&.requested_at.present? && row.requested_at > THROTTLE.ago
  end

  def set_owned_workout
    @workout = current_user.workouts.find_by!(uuid: Allure::ShortId.decode(params[:workout_id]))
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
