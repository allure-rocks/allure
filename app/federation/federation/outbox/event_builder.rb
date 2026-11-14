# frozen_string_literal: true

require "digest"

module Federation
  module Outbox
    class EventBuilder
      class IdentityConflict < StandardError; end

      def self.event_uuid_for(object_uri:, activity_type:, idempotency_key:)
        digest = Digest::SHA256.hexdigest([ object_uri, activity_type, idempotency_key ].join("\0"))[0, 32]
        [ digest[0, 8], digest[8, 4], digest[12, 4], digest[16, 4], digest[20, 12] ].join("-")
      end

      def self.activity_uri_for(object_uri:, activity_type:, idempotency_key:)
        event_uuid = event_uuid_for(object_uri:, activity_type:, idempotency_key:)
        "#{object_uri}/activities/#{event_uuid}"
      end

      def initialize(actor:, subject_type:, subject_id:, activity_type:, object_uri:, payload:, audience:, idempotency_key:, workout_publication_id: nil, segment_publication_id: nil)
        @actor = actor
        @subject_type = subject_type
        @subject_id = subject_id
        @activity_type = activity_type
        @object_uri = object_uri
        @payload = payload.deep_stringify_keys
        @audience = audience.deep_stringify_keys
        @idempotency_key = idempotency_key
        @workout_publication_id = projected_subject_id(workout_publication_id, "WorkoutPublication")
        @segment_publication_id = projected_subject_id(segment_publication_id, "SegmentPublication")
      end

      def call!
        event_uuid = self.class.event_uuid_for(
          object_uri: @object_uri,
          activity_type: @activity_type,
          idempotency_key: @idempotency_key
        )
        activity_uri = "#{@object_uri}/activities/#{event_uuid}"
        payload = @payload.merge("id" => activity_uri)
        event = FederationOutboxEvent.find_by(activity_uri:)
        unless event
          begin
            event = FederationOutboxEvent.create!(
              actor: @actor,
              subject_type: @subject_type,
              subject_id: @subject_id,
              workout_publication_id: @workout_publication_id,
              segment_publication_id: @segment_publication_id,
              event_uuid:,
              activity_type: @activity_type,
              activity_uri:,
              object_uri: @object_uri,
              payload:,
              audience: @audience
            )
          rescue ActiveRecord::RecordNotUnique
            event = FederationOutboxEvent.find_by!(activity_uri:)
          end
        end
        verify_identity!(event, event_uuid:, payload:)
        event
      end

      private

      # The subject FK defaults to the subject id for publication subjects, so
      # callers cannot accidentally create an event with a dangling subject.
      def projected_subject_id(given, subject_type)
        given.nil? && @subject_type == subject_type ? @subject_id : given
      end

      def verify_identity!(event, event_uuid:, payload:)
        expected = {
          actor_id: @actor.id,
          subject_type: @subject_type,
          subject_id: @subject_id,
          workout_publication_id: @workout_publication_id,
          segment_publication_id: @segment_publication_id,
          event_uuid: event_uuid,
          activity_type: @activity_type,
          object_uri: @object_uri,
          payload:,
          audience: @audience
        }
        return if expected.all? { |attribute, value| event.public_send(attribute).to_s == value.to_s || event.public_send(attribute) == value }

        raise IdentityConflict, "outbox event identity conflicts with the existing activity"
      end
    end
  end
end
