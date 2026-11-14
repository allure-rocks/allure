# frozen_string_literal: true

# Every comment gesture answers the same way (PLAN_COMMENTS.md §11.1): inside
# the card's Turbo Frame the card re-renders, so only the thread changes;
# without one the request returns to the thread's own page, carrying a refusal
# as a flash. A reader who can no longer see the thread never gets it back.
module CommentCardRendering
  extend ActiveSupport::Concern

  private

  def render_comment_card(target, status: :ok, composer: nil)
    if request.headers["Turbo-Frame"].present?
      return render partial: "comments/card", locals: { target:, composer: }, status:
    end

    flash[:alert] = composer[:message] if composer&.dig(:message)
    redirect_to comment_thread_location(target), status: :see_other
  end

  def comment_thread_location(target)
    return feed_path if Comments::Post.permission(user: current_user, target:) == :denied && !own_workout?(target)

    helpers.comment_thread_path(target)
  end

  def own_workout?(target) = target.is_a?(Workout) && target.user_id == current_user&.id
end
