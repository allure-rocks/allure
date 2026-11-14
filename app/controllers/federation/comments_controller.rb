# frozen_string_literal: true

module Federation
  # A local author's comment as an ActivityPub object (PLAN_COMMENTS.md
  # §6.5). A public comment in its thread answers anyone, signed or not, so a
  # peer can resolve a reply by its id. A followers comment is never fetched
  # — its host already holds it and such threads are never relayed — and a
  # withdrawn one is gone: both answer 404, like every unavailable object.
  class CommentsController < ProtocolController
    def show
      comment = ::Comment.find_by_short_id!(params[:id])
      return render_not_found unless comment.local_author? && comment.active? && comment.audience == "public"

      response.headers["Cache-Control"] = "private, no-store"
      render_protocol_json(
        Federation::Serializers::CommentNote.new(comment:).call,
        status: :ok,
        content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB
      )
    rescue ActiveRecord::RecordNotFound, Federation::Serializers::CommentNote::Unavailable
      render_not_found
    end
  end
end
