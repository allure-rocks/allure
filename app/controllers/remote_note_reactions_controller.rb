# frozen_string_literal: true

# The local reaction gesture on a received note (PLAN_REACTIONS.md §4.4). Same
# toggle semantics as WorkoutReactionsController; the policy requires an active
# note the viewer is entitled to, and the replacement of the reaction delivers
# the outbound Like or Undo.
class RemoteNoteReactionsController < ApplicationController
  def update
    raise ActiveRecord::RecordNotFound unless Allure::Federation::Config.enabled?

    @note = RemoteNote.find(params[:id])
    Reactions::Toggle.new(user: current_user, target: @note, kind: reaction_kind).call!
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

  def reaction_kind
    params.require(:reaction).permit(:kind)[:kind]
  end

  def render_bar
    return redirect_back fallback_location: remote_note_path(@note), status: :see_other if request.headers["Turbo-Frame"].blank?

    summary = Reactions::Summaries.new(targets: [ @note ], viewer: current_user.actor).call.fetch(@note)
    render partial: "reactions/bar", locals: { target: @note, summary:, reactable: true }
  end
end
