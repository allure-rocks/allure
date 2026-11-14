# frozen_string_literal: true

module Federation
  module Outbox
    # The ActivityPub Like for a reaction on a received note (PLAN_REACTIONS
    # §4.3). The activity identity is the reaction's stored URI, and the
    # reaction type travels in `_allure_reaction`, a private extension an
    # external peer safely ignores — an absent property means the neutral
    # `like`, which is exactly what those peers send.
    class ReactionLike
      def initialize(reaction:, idempotency_key:)
        @reaction = reaction
        @idempotency_key = idempotency_key
      end

      def call!
        raise ArgumentError, "only a reaction to a received note federates" unless target

        EventBuilder.new(
          actor: @reaction.actor,
          subject_type: "Actor",
          subject_id: @reaction.actor_id,
          activity_type: "Like",
          object_uri: @reaction.actor.uri,
          idempotency_key: @idempotency_key,
          payload: {
            "type" => "Like",
            "actor" => @reaction.actor.uri,
            "object" => target.object_uri,
            "_allure_reaction" => @reaction.kind
          },
          audience: { "to" => [ target.actor.uri ], "cc" => [] }
        ).call!
      end

      private

      def target = @reaction.remote_note
    end
  end
end
