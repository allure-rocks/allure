# frozen_string_literal: true

# Posting a comment or a reply on a received note (docs/dev/COMMENTS.md,
# §8.1): the comment is stored here and sent to the note's origin, which hosts
# the thread. Denial is 404, never 403; a thread the origin's profile closed
# or a refused text re-renders the card with its explanation and the text the
# reader typed.
class RemoteNoteCommentsController < ApplicationController
  include CommentCardRendering

  before_action :set_note
  # The same per-account bound as on a workout (docs/dev/COMMENTS.md).
  rate_limit to: 20, within: 1.minute, only: :create, by: -> { current_user.id },
             with: -> { render_comment_card(@note, status: :too_many_requests, composer: refused(:rate_limited)) }

  # The thread alone, the page a phone opens from the note (DESIGN.md §10.20).
  def index
    raise ActiveRecord::RecordNotFound if @note.deleted?

    @card = helpers.comment_card_for(@note)
    raise ActiveRecord::RecordNotFound unless @card.visible?

    @view = Federation::RemoteNoteView.new(@note)
  end

  def create
    Comments::Post.new(
      user: current_user, target: @note, body: comment_params[:body], parent_id: comment_params[:parent_id]
    ).call!
    render_comment_card(@note)
  rescue Comments::Post::NotAllowed
    raise ActiveRecord::RecordNotFound
  rescue Comments::Post::Closed
    render_comment_card(@note, status: :unprocessable_content, composer: refused(:closed))
  rescue Comments::Post::Invalid => error
    render_comment_card(@note, status: :unprocessable_content, composer: refused(error.reason))
  end

  private

  def set_note
    raise ActiveRecord::RecordNotFound unless Allure::Federation::Config.enabled?

    @note = RemoteNote.find(params[:id])
  end

  def comment_params
    params.fetch(:comment, {}).permit(:body, :parent_id)
  end

  def refused(reason)
    {
      parent_id: comment_params[:parent_id].presence,
      body: comment_params[:body].to_s,
      message: t("comments.errors.#{reason}")
    }
  end
end
