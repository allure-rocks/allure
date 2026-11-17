# frozen_string_literal: true

module Federation
  module Inbox
    # The thread host stops relaying a comment (docs/dev/COMMENTS.md): the
    # comment left its thread there — deleted, removed, or with its author.
    # A third party's relayed copy leaves the thread here with its words; this
    # instance's own comment becomes removed by the owner, which its author
    # sees. Only the host undoes its relay; an unknown or withdrawn comment
    # changes nothing.
    class CommentRelayUndo
      def initialize(item:, activity:, now: Time.current)
        @item = item
        @activity = activity
        @now = now
      end

      def call!
        comment = find_comment
        return unless comment
        raise Rejected, "only the thread host undoes its relay" unless comment.remote_note&.actor&.uri == @item.actor_uri
        return comment unless comment.active?

        ::Comment.transaction(requires_new: true) do
          if comment.local_author?
            comment.remove!(reason: Comments::Remove::REASON, at: @now)
          else
            comment.withdraw_relay!(at: @now)
          end
          Comments::Notifier.withdraw!(comment)
        end
        comment
      end

      private

      def find_comment
        object = @activity["object"]
        return unless object.is_a?(Hash)

        by_relay = ::Comment.find_by(relay_activity_uri: object["id"]) if object["id"].is_a?(String)
        by_relay || (::Comment.find_by(uri: object["object"]) if object["object"].is_a?(String))
      end
    end
  end
end
