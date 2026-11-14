# frozen_string_literal: true

module Comments
  # The author takes their own comment back (PLAN_COMMENTS.md §5.2). The row
  # keeps its identity as a deleted comment, the notices it caused go, and a
  # comment that federated sends its Delete wherever its Create may have
  # arrived. A repeated request changes nothing.
  class Delete
    class NotAllowed < StandardError; end

    def self.allowed?(user:, comment:)
      actor_id = user&.actor&.id
      actor_id.present? && comment.actor_id == actor_id
    end

    def initialize(user:, comment:, now: Time.current)
      @user = user
      @comment = comment
      @now = now
    end

    def call!
      raise NotAllowed, "only the author deletes a comment" unless self.class.allowed?(user: @user, comment: @comment)

      events = []
      Comment.transaction do
        was_active = @comment.active?
        @comment.mark_deleted!(at: @now)
        Comments::Notifier.withdraw!(@comment)
        if was_active && @comment.deleted?
          events << Federation::Outbox::CommentDelete.new(comment: @comment, now: @now).call!
          # A thread hosted here stops relaying it (PLAN_COMMENTS.md §8.4).
          events << Federation::Outbox::CommentUnannounce.new(comment: @comment, now: @now).call! if @comment.workout
        end
      end
      Comments::Outbound.enqueue!(events)
      @comment
    end
  end
end
