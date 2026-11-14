# frozen_string_literal: true

module Federation
  module Serializers
    # A local comment as an ActivityPub Note (PLAN_COMMENTS.md §6.2): plain
    # text escaped into the content, the publication or the parent comment as
    # `inReplyTo`, the publication as `context` so a reader that never saw the
    # parent still knows the thread, and no name, tag, attachment, or url. The
    # audience is the host's business: a reader's comment goes to the thread
    # host alone, and only the host's own comment carries the publication's
    # audience.
    class CommentNote
      class Unavailable < StandardError; end

      def initialize(comment:)
        @comment = comment
      end

      def call
        raise Unavailable, "only a local author's comment is serialized" unless @comment.local_author?

        audience = self.class.audience_for(@comment)
        {
          "@context" => WorkoutNote::ACTIVITY_STREAMS_CONTEXT,
          "id" => @comment.uri,
          "type" => "Note",
          "attributedTo" => @comment.actor.uri,
          "inReplyTo" => @comment.in_reply_to_uri,
          "context" => @comment.thread_object_uri,
          "content" => content,
          "published" => @comment.published_at.utc.iso8601,
          "to" => audience.fetch("to"),
          "cc" => audience.fetch("cc")
        }
      end

      def self.audience_for(comment)
        host = comment.thread_host_actor
        raise Unavailable, "the thread has no host" unless host
        return { "to" => [ host.uri ], "cc" => [] } unless comment.by_thread_host?

        followers = "#{comment.actor.uri}/followers"
        if comment.audience == "followers"
          { "to" => [ followers ], "cc" => [] }
        else
          { "to" => [ WorkoutNote::PUBLIC_AUDIENCE ], "cc" => [ followers ] }
        end
      end

      private

      # The WorkoutNote rule: escaped text, line breaks as <br>.
      def content
        ERB::Util.html_escape(@comment.body).to_str.gsub("\n", "<br>")
      end
    end
  end
end
