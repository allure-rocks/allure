# frozen_string_literal: true

# The local reaction gesture on a workout publication (docs/dev/REACTIONS.md).
# One PUT toggles the viewer's active reaction: an absent one is created, the
# same one is withdrawn, another one replaces it. The target is the workout,
# not the publication identity, so a later republish keeps the counts. Denial
# is 404, never 403; the owner never reacts to their own workout.
class WorkoutReactionsController < ApplicationController
  before_action :set_workout

  def update
    Reactions::Toggle.new(user: current_user, target: @workout, kind: reaction_kind).call!
    render_bar
  rescue Reactions::Toggle::NotAllowed
    raise ActiveRecord::RecordNotFound
  rescue Reactions::Toggle::InvalidKind
    head :unprocessable_content
  rescue ActiveRecord::RecordNotUnique
    # Two simultaneous gestures raced on the one-active-reaction index: the
    # first one won, so the bar simply shows the current state.
    render_bar
  end

  private

  def set_workout
    @workout = Workout.find_by_short_id!(params[:workout_id])
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  def reaction_kind
    params.require(:reaction).permit(:kind)[:kind]
  end

  def render_bar
    return redirect_back fallback_location: workout_path(@workout), status: :see_other if request.headers["Turbo-Frame"].blank?

    summary = Reactions::Summaries.new(targets: [ @workout ], viewer: current_user.actor).call.fetch(@workout)
    render partial: "reactions/bar", locals: { target: @workout, summary:, reactable: true }
  end
end
