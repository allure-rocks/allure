# frozen_string_literal: true

module Comments
  # The comment notice (PLAN_COMMENTS.md §10): the owner of a local thread
  # hears about every comment, and the local author of a parent hears about
  # its replies. Notifications::Create skips the author, honours each
  # account's switch, and its unique index collapses an owner who is also the
  # parent's author into one entry.
  module Notifier
    KIND = "comment"

    def self.notify!(comment)
      recipients_for(comment).each do |user|
        ::Notifications::Create.new(user:, kind: KIND, actor: comment.actor, subject: comment).call!
      end
    end

    def self.withdraw!(comment)
      ::Notifications::Withdraw.new(kind: KIND, subject: comment).call!
    end

    def self.recipients_for(comment)
      parent_actor = comment.parent&.actor
      parent_user = parent_actor.user if parent_actor&.local?
      [ comment.workout&.user, parent_user ].compact.uniq
    end
    private_class_method :recipients_for
  end
end
