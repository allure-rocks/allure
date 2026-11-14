# frozen_string_literal: true

module Comments
  # With a relay, a reply can arrive before the comment it answers
  # (PLAN_COMMENTS.md §7.2, §14 Slice 3): it waits as a root on the thread its
  # `context` names, keeping the answered URI, and the answered comment adopts
  # it when it lands — under its root, one level deep.
  module Relink
    def self.call!(comment)
      root = comment.parent || comment
      Comment.for_target(comment.target).roots
        .where(in_reply_to_uri: comment.uri)
        .where.not(id: [ comment.id, root.id ])
        .find_each do |orphan|
          next if orphan.replies.exists?

          orphan.update!(parent: root)
        end
    end
  end
end
