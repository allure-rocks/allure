# frozen_string_literal: true

module Federation
  module Outbox
    # The thread host stops relaying a comment that left its thread — deleted
    # by its author, removed by the owner, or taken out with a blocked or
    # deleted account (PLAN_COMMENTS.md §6.3, §8.4). The Undo goes exactly
    # where the Announce was attempted; deliveries never attempted are
    # cancelled and the Announce's payload is redacted, so the words travel no
    # further and stay nowhere in the outbox.
    class CommentUnannounce
      def initialize(comment:, now: Time.current)
        @comment = comment
        @now = now
      end

      def call!
        host = @comment.thread_host_actor
        return unless host&.local?

        announce = FederationOutboxEvent.find_by(activity_uri: CommentAnnounce.activity_uri_for(@comment, host))
        return unless announce

        recipients = Workouts::PublicationWithdrawal.recipient_uris_for(announce)
        Workouts::PublicationWithdrawal.cancel_unattempted!(announce)
        PayloadRedactor.new(event: announce, now: @now).call!
        return if recipients.empty?

        EventBuilder.new(
          actor: host,
          subject_type: announce.subject_type,
          subject_id: announce.subject_id,
          workout_publication_id: announce.workout_publication_id,
          activity_type: "Undo",
          object_uri: host.uri,
          idempotency_key: "comment:undo-announce:#{@comment.uri}",
          payload: {
            "type" => "Undo",
            "actor" => host.uri,
            "object" => { "type" => "Announce", "id" => announce.activity_uri, "object" => @comment.uri },
            "to" => recipients,
            "cc" => []
          },
          audience: { "recipients" => recipients, "to" => recipients, "cc" => [] }
        ).call!
      end
    end
  end
end
