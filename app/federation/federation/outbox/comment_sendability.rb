# frozen_string_literal: true

module Federation
  module Outbox
    # A comment's Create, and the host's Announce relaying it, travel only
    # while the comment is still in its thread (docs/dev/COMMENTS.md): a
    # comment deleted or removed before its activity left never leaves.
    # Expansion and delivery both ask, so an unexpanded event is cancelled as
    # surely as a queued delivery.
    module CommentSendability
      def self.sendable?(event)
        case event.activity_type
        when "Create"
          return true unless Comment.local_uri?(event.object_uri)

          Comment.active.exists?(uri: event.object_uri)
        when "Announce"
          object = event.payload.is_a?(Hash) ? event.payload["object"] : nil
          object.is_a?(Hash) && Comment.active.exists?(uri: object["id"])
        else
          true
        end
      end
    end
  end
end
