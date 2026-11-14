# frozen_string_literal: true

require "digest"
require "securerandom"

module Reactions
  # The durable identity of a reaction (PLAN_REACTIONS.md §4.3). A reaction to
  # a received note carries the URI of the ActivityPub Like that will be
  # delivered, derived from the local actor and a fresh key, so the outbox
  # event and its later Undo always reference the same activity. A purely
  # local reaction has no protocol identity and receives a local URI, exactly
  # like a local follow (Federation::Follow#local_follow_uri).
  class Wire
    class NotFederated < StandardError; end

    def self.key_for(target:)
      raise NotFederated, "a local target has no federated identity" unless federated?(target)

      "like:#{target.object_uri}:#{SecureRandom.uuid}"
    end

    def self.uri_for(actor:, key:)
      Federation::Outbox::EventBuilder.activity_uri_for(
        object_uri: actor.uri, activity_type: "Like", idempotency_key: key
      )
    end

    def self.local_uri_for(actor:, target:)
      digest = Digest::SHA256.hexdigest(
        [ actor.id, target.class.name, target.id, SecureRandom.uuid ].join(":")
      )[0, 32]
      "#{Allure::Federation.config.base_url}/local_reactions/#{digest}"
    end

    def self.federated?(target) = target.is_a?(RemoteNote)
  end
end
