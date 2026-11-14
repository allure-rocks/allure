# frozen_string_literal: true

module Federation
  module Outbox
    # The invited account's answer to a remote owner's Invite
    # (PLAN_TOGETHER.md §7): an `Accept` or a `Reject` of that Invite, then,
    # for a confirmation it takes back, an `Undo` of its `Accept`. Each is the
    # account's own activity, addressed to the owner alone; identities are
    # deterministic, so the Undo names the Accept without remembering it.
    class ParticipationAnswer
      ANSWERS = %w[Accept Reject].freeze

      def self.key_for(type, participation) = "participation:#{type.downcase}:#{participation.invite_activity_uri}"

      def self.accept_uri_for(participation, actor)
        EventBuilder.activity_uri_for(object_uri: actor.uri, activity_type: "Accept",
                                      idempotency_key: key_for("Accept", participation))
      end

      def initialize(participation:)
        @participation = participation
      end

      def answer!(type)
        raise ArgumentError, "unknown answer #{type}" unless ANSWERS.include?(type)

        build(type, @participation.invite_activity_uri, key: self.class.key_for(type, @participation))
      end

      def undo_accept!
        accept_uri = self.class.accept_uri_for(@participation, actor)
        build("Undo", { "type" => "Accept", "id" => accept_uri, "object" => @participation.invite_activity_uri },
              key: "participation:undo-accept:#{@participation.invite_activity_uri}")
      end

      private

      def actor = @participation.recipient_actor

      def build(type, object, key:)
        owner = @participation.origin_actor
        audience = { "to" => [ owner.uri ], "cc" => [] }
        EventBuilder.new(
          actor:,
          subject_type: "Actor",
          subject_id: actor.id,
          activity_type: type,
          object_uri: actor.uri,
          idempotency_key: key,
          payload: { "type" => type, "actor" => actor.uri, "object" => object, **audience },
          audience:
        ).call!
      end
    end
  end
end
