# frozen_string_literal: true

# The owner's live switch on a workout's thread (docs/dev/COMMENTS.md).
# Anyone else gets 404.
class WorkoutCommentThreadsController < ApplicationController
  include CommentCardRendering

  def update
    workout = Workout.find_by_short_id!(params[:workout_id])
    Comments::Close.new(user: current_user, workout:, closed: closed?).call!
    render_comment_card(workout)
  rescue Comments::Close::NotAllowed, ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  private

  def closed? = ActiveModel::Type::Boolean.new.cast(params[:closed]) == true
end
