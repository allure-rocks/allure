# frozen_string_literal: true

module Federation
  module Outbox
    # The Create carrying a local author's comment (docs/dev/COMMENTS.md,
    # §8.1, §8.2). A reader's comment is the reader's own activity, addressed
    # to the thread host; the owner's comment rides on the publication it
    # answers, as a secondary event that only reaches the publication's
    # recipients (§9).
    class CommentCreate
      def self.key_for(comment) = "comment:create:#{comment.uri}"

      def initialize(comment:, publication: nil)
        @comment = comment
        @publication = publication
      end

      def call!
        note = Serializers::CommentNote.new(comment: @comment).call
        EventBuilder.new(
          actor: @comment.actor,
          **subject,
          activity_type: "Create",
          object_uri: @comment.uri,
          idempotency_key: self.class.key_for(@comment),
          payload: {
            "type" => "Create",
            "actor" => @comment.actor.uri,
            "object" => note,
            "to" => note["to"],
            "cc" => note["cc"]
          },
          audience: { "to" => note["to"], "cc" => note["cc"] }
        ).call!
      end

      private

      def subject
        if @publication
          { subject_type: "WorkoutPublication", subject_id: @publication.id, workout_publication_id: @publication.id }
        else
          { subject_type: "Actor", subject_id: @comment.actor_id }
        end
      end
    end
  end
end
