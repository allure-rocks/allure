# frozen_string_literal: true

module Federation
  module Outbox
    # The ActivityPub Undo for a withdrawn reaction on a received note
    # (docs/dev/REACTIONS.md). The nested object is the Like identity stored
    # on the reaction row, so the peer always retires the activity it admitted.
    class ReactionUndo
      def initialize(reaction:)
        @reaction = reaction
      end

      def call!
        raise ArgumentError, "only a reaction to a received note federates" unless target

        EventBuilder.new(
          actor: @reaction.actor,
          subject_type: "Actor",
          subject_id: @reaction.actor_id,
          activity_type: "Undo",
          object_uri: @reaction.actor.uri,
          idempotency_key: "undo-like:#{@reaction.uri}",
          payload: {
            "type" => "Undo",
            "actor" => @reaction.actor.uri,
            "object" => { "type" => "Like", "id" => @reaction.uri }
          },
          audience: { "to" => [ target.actor.uri ], "cc" => [] }
        ).call!
      end

      private

      def target = @reaction.remote_note
    end
  end
end
