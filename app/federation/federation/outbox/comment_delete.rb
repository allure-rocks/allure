# frozen_string_literal: true

module Federation
  module Outbox
    # The author's withdrawal of a comment that federated (docs/dev/COMMENTS.md
    # §6.3, §8.1, §8.2). It goes exactly where the Create may have arrived —
    # the attempted set of that Create, the publication-withdrawal rule — and
    # shares the Create's subject. Deliveries the Create never attempted are
    # cancelled and the Create's payload is redacted, so the words never leave
    # again and are kept nowhere; nothing is sent when no instance can hold
    # them.
    class CommentDelete
      def initialize(comment:, now: Time.current)
        @comment = comment
        @now = now
      end

      def call!
        create_event = create_event_for(@comment)
        return unless create_event

        recipients = Workouts::PublicationWithdrawal.recipient_uris_for(create_event)
        Workouts::PublicationWithdrawal.cancel_unattempted!(create_event)
        PayloadRedactor.new(event: create_event, now: @now).call!
        return if recipients.empty?

        EventBuilder.new(
          actor: create_event.actor,
          subject_type: create_event.subject_type,
          subject_id: create_event.subject_id,
          workout_publication_id: create_event.workout_publication_id,
          activity_type: "Delete",
          object_uri: @comment.uri,
          idempotency_key: "comment:delete:#{@comment.uri}",
          payload: {
            "type" => "Delete",
            "actor" => create_event.actor.uri,
            "object" => {
              "id" => @comment.uri,
              "type" => "Tombstone",
              "formerType" => "Note",
              "deleted" => @comment.deleted_at.utc.iso8601
            },
            "to" => recipients,
            "cc" => []
          },
          audience: { "recipients" => recipients, "to" => recipients, "cc" => [] }
        ).call!
      end

      private

      def create_event_for(comment)
        return if comment.activity_uri.blank?

        FederationOutboxEvent.find_by(activity_uri: comment.activity_uri, activity_type: "Create")
      end
    end
  end
end
