# frozen_string_literal: true

module Federation
  module Serializers
    class Tombstone
      # `at` lets a Delete activity embed the tombstone before the actor row is
      # tombstoned. Event creation validates that the actor is still current,
      # so the timestamp must be known in advance.
      def initialize(actor:, at: nil)
        @actor = actor
        @at = at
      end

      def call
        {
          "@context" => "https://www.w3.org/ns/activitystreams",
          "id" => @actor.uri,
          "type" => "Tombstone",
          "formerType" => "Person",
          "deleted" => (@at || @actor.tombstoned_at).utc.iso8601
        }
      end
    end
  end
end
