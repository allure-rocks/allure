# frozen_string_literal: true

# Taking a comment out of its thread (docs/dev/COMMENTS.md): the author
# deletes their own, the workout's owner removes anyone else's. Both are
# idempotent; anyone else gets 404, never 403.
class CommentsController < ApplicationController
  include CommentCardRendering

  def destroy
    comment = Comment.find_by_short_id!(params[:id])
    if Comments::Delete.allowed?(user: current_user, comment:)
      Comments::Delete.new(user: current_user, comment:).call!
    elsif Comments::Remove.allowed?(user: current_user, comment:)
      Comments::Remove.new(user: current_user, comment:).call!
    else
      raise ActiveRecord::RecordNotFound
    end
    render_comment_card(comment.target)
  end
end
