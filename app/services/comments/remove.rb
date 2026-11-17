# frozen_string_literal: true

module Comments
  # The owner of a workout takes someone else's comment out of the thread
  # (docs/dev/COMMENTS.md). The comment stays a durable `removed` row, its
  # author still sees it with that state — told through a Reject when the
  # author is on another instance — and replies to it keep their place under a
  # stub. A repeated request changes nothing.
  class Remove
    class NotAllowed < StandardError; end

    REASON = "owner"

    # The owner's own words are deleted, never removed.
    def self.allowed?(user:, comment:)
      workout = comment.workout
      return false unless user && workout && workout.user_id == user.id

      !Comments::Delete.allowed?(user:, comment:)
    end

    def initialize(user:, comment:, now: Time.current)
      @user = user
      @comment = comment
      @now = now
    end

    def call!
      raise NotAllowed, "only the thread host removes a comment" unless self.class.allowed?(user: @user, comment: @comment)

      events = []
      Comment.transaction do
        was_active = @comment.active?
        @comment.remove!(reason: REASON, at: @now)
        Comments::Notifier.withdraw!(@comment)
        if was_active && @comment.removed?
          events << tell_remote_author
          events << Federation::Outbox::CommentUnannounce.new(comment: @comment, now: @now).call!
        end
      end
      Comments::Outbound.enqueue!(events)
      @comment
    end

    private

    def tell_remote_author
      return if @comment.local_author? || @comment.activity_uri.blank?

      Federation::Outbox::CommentReject.new(
        host_actor: @comment.thread_host_actor,
        author_uri: @comment.actor.uri,
        create_activity_uri: @comment.activity_uri,
        comment_uri: @comment.uri,
        reason: "removed"
      ).call!
    end
  end
end
