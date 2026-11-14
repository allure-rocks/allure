# frozen_string_literal: true

module Federation
  module Outbox
    # Builds the ActivityPub Create intent for a publication, and can rebuild
    # its payload once the asynchronous route image has been attached. Kept out
    # of Workouts::Publisher so the render job finalizes the same intent without
    # duplicating the Note serialization.
    class PublicationCreate
      def initialize(publication:)
        @publication = publication
      end

      # `preparing` marks an intent whose route image is still rendering;
      # `Recovery` finalizes stale intents so delivery can never be stranded.
      def intent!(status: "pending")
        payload = activity_payload
        event = EventBuilder.new(
          actor: @publication.actor,
          subject_type: "WorkoutPublication",
          subject_id: @publication.id,
          workout_publication_id: @publication.id,
          activity_type: "Create",
          object_uri: @publication.object_uri,
          idempotency_key: "publication:create:#{@publication.object_uri}",
          payload:,
          audience: { "to" => payload.dig("object", "to"), "cc" => payload.dig("object", "cc") }
        ).call!
        event.update_column(:status, status) if status != event.status
        event
      end

      # Refreshes a still-preparing intent with the now-complete Note and hands
      # it to expansion. Safe to call more than once. Payload is immutable
      # through ordinary updates, so the refresh writes through the relation,
      # like outbox payload redaction.
      def finalize!(event)
        return event unless event.preparing?

        FederationOutboxEvent.where(id: event.id).update_all(
          payload: activity_payload("id" => event.activity_uri),
          status: "pending",
          updated_at: Time.current
        )
        event.reload
      end

      private

      def activity_payload(extra = {})
        actor = @publication.actor
        note = Serializers::WorkoutNote.new(publication: @publication, actor:).call
        {
          "type" => "Create",
          "actor" => actor.uri,
          "object" => note,
          "to" => note.fetch("to"),
          "cc" => note.fetch("cc")
        }.merge(extra)
      end
    end
  end
end
