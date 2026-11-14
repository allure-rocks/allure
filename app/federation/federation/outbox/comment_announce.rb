# frozen_string_literal: true

module Federation
  module Outbox
    # The thread host relays a comment it accepted to every instance its public
    # publication went to (PLAN_COMMENTS.md §6.6, §8.4): an Announce of the
    # comment as its author wrote it — a remote author's object exactly as
    # received, so receivers can compare it with the author's own copy. It is
    # a secondary publication event (§9) and never covers a followers thread.
    class CommentAnnounce
      def self.key_for(comment) = "comment:announce:#{comment.uri}"

      # The Announce's identity is deterministic, so the withdrawal finds it
      # without remembering it on the row.
      def self.activity_uri_for(comment, host)
        EventBuilder.activity_uri_for(object_uri: host.uri, activity_type: "Announce", idempotency_key: key_for(comment))
      end

      def initialize(comment:, publication:)
        @comment = comment
        @publication = publication
      end

      def call!
        raise ArgumentError, "only a public thread is relayed" unless @publication.audience == "public"

        host = @publication.actor
        followers = "#{host.uri}/followers"
        audience = { "to" => [ Serializers::WorkoutNote::PUBLIC_AUDIENCE ], "cc" => [ followers ] }
        EventBuilder.new(
          actor: host,
          subject_type: "WorkoutPublication",
          subject_id: @publication.id,
          workout_publication_id: @publication.id,
          activity_type: "Announce",
          object_uri: host.uri,
          idempotency_key: self.class.key_for(@comment),
          payload: { "type" => "Announce", "actor" => host.uri, "object" => announced_object, **audience },
          audience:
        ).call!
      end

      private

      def announced_object
        return Serializers::CommentNote.new(comment: @comment).call if @comment.local_author?

        @comment.raw
      end
    end
  end
end
