# frozen_string_literal: true

module Federation
  module Inbox
    # The thread host's Reject of a comment written here (PLAN_COMMENTS.md
    # §7.4). Its object is the comment's Create; only the host of the received
    # note may send it. `removed` takes an accepted comment out of the thread;
    # any other reason means the host never accepted it. An absent or unknown
    # reason is the generic refusal, never a rejection of the Reject.
    class CommentRefusal
      REASONS = (::Comment::REMOVAL_REASONS - %w[owner blocked actor_deleted]).freeze

      def initialize(item:, activity:, now: Time.current)
        @item = item
        @activity = activity
        @now = now
      end

      def call!
        comment = ::Comment.find_by(activity_uri: create_activity_uri)
        raise Rejected, "reject references an unknown follow or comment" unless comment&.local_author?

        note = comment.remote_note
        raise Rejected, "reject actor does not host the comment's thread" unless note && note.actor.uri == @item.actor_uri
        return comment unless comment.active?

        ::Comment.transaction(requires_new: true) do
          if reason == "removed"
            comment.remove!(reason: Comments::Remove::REASON, at: @now)
          else
            comment.reject!(reason: REASONS.include?(reason) ? reason : "unknown", at: @now)
          end
          Comments::Notifier.withdraw!(comment)
        end
        comment
      end

      private

      def create_activity_uri
        object = @activity["object"]
        object.is_a?(Hash) ? object["id"] : object
      end

      def reason = @activity["_allure_reason"].to_s
    end
  end
end
