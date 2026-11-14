# frozen_string_literal: true

module Federation
  module Signature
    # Finds the remote actor whose key verifies a prepared signature. The
    # cached key is tried first, whatever its age: a peer's key rarely
    # changes, and its instance may be slow, down, or — for an account it has
    # just deleted — answering 410 for good. Only when the cached key does
    # not verify is the actor fetched again, once, so a rotated key (a reset
    # instance) is picked up at once instead of after the cache expires.
    #
    # That fetch runs in the request thread of an unauthenticated request, so
    # it is bounded (PLAN_M5 §12.2): an actor fetched less than
    # `REFRESH_FLOOR` ago is not fetched again, every fetch is metered by
    # `Safety::ResolutionAttempts`, and at most `Safety::ResolutionGate::SLOTS`
    # run at once.
    #
    # With `known_only: true` (signed GETs) an actor this instance has no row
    # for is never fetched: only a known actor can hold a follow or be
    # addressed by an outbox item, so an unknown signer gains nothing over an
    # anonymous request and must not cost a fetch or a row.
    class SignerResolution
      Result = Data.define(:actor, :verification)

      REFRESH_FLOOR = 5.minutes

      def initialize(actor_resolver:, verifier:)
        @actor_resolver = actor_resolver
        @verifier = verifier
      end

      def call(actor_uri:, prepared:, persist: true, known_only: false)
        raise ActorResolver::InvalidActor, "actor is blocked" if Safety::Blocks.blocked?(actor_uri)

        cached = Actor.remote.find_by(uri: actor_uri)
        raise ActorResolver::InvalidActor, "actor is tombstoned" if cached&.tombstoned?
        raise ActorResolver::InvalidActor, "signer is unknown" if known_only && cached.nil?

        verification = cached && verify_cached(cached, prepared)
        return Result.new(cached, verification) if verification
        if recently_fetched?(cached)
          raise Verifier::InvalidSignature, "signature does not verify with the recently fetched key"
        end

        actor = resolve(actor_uri, refresh: cached.present?, persist:)
        begin
          raise ActorResolver::InvalidActor, "signer must be a remote actor" unless actor.remote? && !actor.tombstoned?

          Result.new(actor, @verifier.verify(prepared:, public_key: actor.public_key_pem))
        rescue ActorResolver::InvalidActor, Verifier::InvalidSignature
          Safety::ResolutionAttempts.record_failure(actor_uri)
          raise
        end
      end

      private

      def resolve(actor_uri, refresh:, persist:)
        Safety::ResolutionAttempts.check!(actor_uri)
        Safety::ResolutionGate.hold do
          if refresh
            @actor_resolver.resolve(actor_uri, refresh: true, persist:)
          else
            @actor_resolver.resolve(actor_uri, persist:)
          end
        end
      rescue Safety::ResolutionGate::Busy, Safety::ResolutionAttempts::RecentlyFailed
        raise
      rescue ActorResolver::InvalidActor, ActorResolver::FetchError
        Safety::ResolutionAttempts.record_failure(actor_uri)
        raise
      end

      def recently_fetched?(actor)
        actor&.last_fetched_at.present? && actor.last_fetched_at > REFRESH_FLOOR.ago
      end

      def verify_cached(actor, prepared)
        return if actor.public_key_pem.blank? || actor.public_key_id != prepared.signature["keyid"]

        @verifier.verify(prepared:, public_key: actor.public_key_pem)
      rescue Verifier::InvalidSignature
        nil
      end
    end
  end
end
