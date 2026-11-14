# frozen_string_literal: true

# Posting a comment or a reply on a workout's thread (PLAN_COMMENTS.md §5.1).
# The thread is the workout's, one per publication audience, not one
# publication's, so a republished workout keeps it (PLAN_AUDIENCES.md §6). Denial is 404, never 403; a closed thread or a refused text
# re-renders the card with its explanation and the text the reader typed.
class WorkoutCommentsController < ApplicationController
  include CommentCardRendering

  before_action :set_workout
  # A person converses; a script floods. The bound is per account and far above
  # any conversation (PLAN_COMMENTS.md §4.4).
  rate_limit to: 20, within: 1.minute, only: :create, by: -> { current_user.id },
             with: -> { render_comment_card(@workout, status: :too_many_requests, composer: refused(:rate_limited)) }

  # The thread alone, the page a phone opens from the workout (DESIGN.md
  # §10.20). Whoever reads the card on the workout page reads it here; anyone
  # else gets a 404.
  def index
    @card = helpers.comment_card_for(@workout)
    raise ActiveRecord::RecordNotFound unless @card.visible?

    @display_workout = if @workout.user == current_user || @card.publication.nil?
      @workout
    else
      Workouts::PublicationView.new(@card.publication, principal: Workouts::PublicationPrincipal.browser(current_user))
    end
  end

  def create
    Comments::Post.new(
      user: current_user, target: @workout, body: comment_params[:body], parent_id: comment_params[:parent_id],
      audience: comment_params[:audience]
    ).call!
    render_comment_card(@workout)
  rescue Comments::Post::NotAllowed
    raise ActiveRecord::RecordNotFound
  rescue Comments::Post::Closed
    render_comment_card(@workout, status: :unprocessable_content, composer: refused(:closed))
  rescue Comments::Post::Invalid => error
    render_comment_card(@workout, status: :unprocessable_content, composer: refused(error.reason))
  end

  private

  def set_workout
    @workout = Workout.find_by_short_id!(params[:workout_id])
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  def comment_params
    params.fetch(:comment, {}).permit(:body, :parent_id, :audience)
  end

  # The refused text goes back into the composer it came from.
  def refused(reason)
    {
      parent_id: comment_params[:parent_id].presence,
      body: comment_params[:body].to_s,
      message: t("comments.errors.#{reason}")
    }
  end
end
