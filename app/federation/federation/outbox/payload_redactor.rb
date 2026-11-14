# frozen_string_literal: true

module Federation
  module Outbox
    class PayloadRedactor
      def initialize(event:, now: Time.current)
        @event = event
        @now = now
      end

      def call!
        return @event.reload if @event.payload_redacted_at.present?

        payload_digest = CanonicalJson.digest(@event.payload)
        audience_digest = CanonicalJson.digest(@event.audience)
        envelope = {
          "redacted" => true,
          "activity_uri" => @event.activity_uri,
          "activity_type" => @event.activity_type,
          "actor" => @event.actor.uri,
          "object" => @event.object_uri,
          "audience_digest" => audience_digest,
          "payload_digest" => payload_digest
        }
        # Payload is immutable through ordinary updates; redaction is the
        # controlled terminal exception, so it writes through the relation and
        # bypasses the model-level readonly guard.
        FederationOutboxEvent.where(id: @event.id).update_all(
          payload: envelope,
          payload_digest:,
          payload_redacted_at: @now,
          updated_at: @now
        )
        @event.reload
      end
    end
  end
end
