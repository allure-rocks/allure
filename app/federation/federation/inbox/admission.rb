# frozen_string_literal: true

require "json"

module Federation
  module Inbox
    class Admission
      class InvalidRequest < StandardError; end
      class UnknownRecipient < StandardError; end
      class Blocked < StandardError; end
      # The sender's actor could not be fetched right now: the sender should
      # try again, not give up on a 401.
      class Unavailable < StandardError; end
      class RateLimited < StandardError
        attr_reader :retry_after

        def initialize(retry_after)
          @retry_after = retry_after
          super("inbound rate limit exceeded")
        end
      end
      AdmissionResult = Data.define(:items, :duplicate) do
        def duplicate? = duplicate
      end

      MAX_BODY_BYTES = 1.megabyte
      PUBLIC_AUDIENCE = "https://www.w3.org/ns/activitystreams#Public"

      def initialize(method:, path:, content_type:, headers:, body:, recipient_actor: nil,
                     actor_resolver: ActorResolver.inbound, verifier: Signature::Verifier.new)
        @method = method.to_s
        @path = path.to_s
        @content_type = content_type.to_s
        @headers = headers.to_h
        @body = body.to_s.b
        @recipient_actor = recipient_actor
        @actor_resolver = actor_resolver
        @verifier = verifier
      end

      def call!
        validate_request!
        prepared_verification = @verifier.prepare(
          method: @method, path: @path, headers: @headers, body: @body
        )
        envelope = parse_envelope
        enforce_safety!(envelope.fetch("actor"))
        return AdmissionResult.new([], true) if unknown_actor_self_deletion?(envelope)

        signer = Signature::SignerResolution.new(actor_resolver: @actor_resolver, verifier: @verifier)
          .call(actor_uri: envelope.fetch("actor"), prepared: prepared_verification, persist: false)
        remote_actor = signer.actor
        validate_signature_owner!(signer.verification, remote_actor, envelope.fetch("actor"))
        persist_remote_actor!(remote_actor)
        recipients = @recipient_actor ? personal_recipient!(envelope, remote_actor) : recipients_for(envelope, remote_actor)
        activity = Federation::Parsers::Activity.new(envelope).call
        admit_all!(recipients:, activity:)
      rescue ActorResolver::Unavailable => error
        raise Unavailable, error.message
      rescue Safety::ResolutionAttempts::Exceeded => error
        raise RateLimited, error.retry_after
      rescue JSON::ParserError, KeyError, TypeError, Signature::Verifier::InvalidSignature,
             ActorResolver::InvalidActor, ActorResolver::FetchError,
             Federation::Parsers::Activity::InvalidActivity,
             ActiveRecord::RecordInvalid => error
        raise InvalidRequest, error.message
      end

      private

      def validate_request!
        raise InvalidRequest, "inbox accepts POST only" unless @method.casecmp?("POST")
        raise InvalidRequest, "activity content type is required" unless Allure::Federation::MediaTypes::ACTIVITY_PUB_ACCEPTED.include?(@content_type)
        raise InvalidRequest, "request body is too large" if @body.bytesize > MAX_BODY_BYTES
        raise InvalidRequest, "recipient actor is invalid" if @recipient_actor && !@recipient_actor.local?
      end

      # Blocks and rate limits run on the claimed actor before any outbound
      # resolution, so a blocked or flooding authority cannot spend our fetch
      # capacity, and nothing is persisted for it (docs/dev/FEDERATION.md–12.2). This
      # limit counts admitted rows; the fetches of requests that never verify
      # are metered by `SignerResolution` itself.
      def enforce_safety!(actor_uri)
        raise Blocked, "actor is blocked" if Safety::Blocks.blocked?(actor_uri)

        domain = Allure::Federation::Authority.domain(actor_uri)
        result = Safety::InboundRateLimiter.check(domain)
        raise RateLimited, result.retry_after unless result.allowed?
      end

      def parse_envelope
        document = JSON.parse(@body)
        raise InvalidRequest, "activity envelope must be an object" unless document.is_a?(Hash)
        %w[id type actor].each do |key|
          raise InvalidRequest, "activity envelope is missing #{key}" unless document[key].is_a?(String) && document[key].present?
        end
        document
      end

      # A personal inbox is not a catch-all: the activity must name that actor
      # in its own type or audience. Without this check any signed activity
      # could be stored against any local account.
      def personal_recipient!(document, remote_actor)
        expected = recipients_for(document, remote_actor)
        return [ @recipient_actor ] if expected.include?(@recipient_actor)

        raise UnknownRecipient, "activity does not address the personal inbox recipient"
      end

      def recipients_for(document, remote_actor)
        recipient_uri = case document["type"]
        when "Follow"
          document["object"] if document["object"].is_a?(String)
        when "Like"
          # The object of a Like is the liked publication, not a recipient: the
          # local author is the addressed actor (docs/dev/REACTIONS.md). The
          # old reading made every HTTP-delivered Like a 404.
          WorkoutPublication.find_by(object_uri: document["object"])&.actor&.uri
        when "Accept"
          own_following(object_uri(document), followed_actor: remote_actor)&.follower_actor&.uri
        when "Undo"
          own_following(object_uri(document), follower_actor: remote_actor)&.followed_actor&.uri ||
            own_reaction(object_uri(document), remote_actor)&.workout&.user&.actor&.uri
        end
        return [ addressed_recipient!(recipient_uri) ] if recipient_uri

        recipients = audience_recipients(document, remote_actor)
        raise UnknownRecipient, "inbox recipient is unknown" if recipients.empty?

        recipients
      end

      def object_uri(document)
        document["object"].is_a?(String) ? document["object"] : document.dig("object", "id")
      end

      # Only a row the sender is party to may route its Accept or Undo
      # (docs/dev/FEDERATION.md). A lookup by URI alone answered 202 for any existing
      # relationship and 404 otherwise, so any signer could test who follows
      # whom — and Follow URIs used to be computable. A row the sender is not
      # party to now answers exactly like an unknown URI.
      def own_following(uri, **party)
        return unless uri.is_a?(String) && party.values.all?(&:persisted?)

        Following.find_by(uri:, **party)
      end

      def own_reaction(uri, remote_actor)
        return unless uri.is_a?(String) && remote_actor.persisted?

        Reaction.find_by(uri:, actor: remote_actor)
      end

      def addressed_recipient!(recipient_uri)
        actor = Actor.local.find_by(uri: recipient_uri)
        raise UnknownRecipient, "inbox recipient is unknown" unless actor && !actor.tombstoned?

        actor
      end

      # An activity that names no local recipient in its own type — a delivered
      # publication or its withdrawal — is addressed the way ActivityPub
      # actually addresses things: either straight at an actor, or at the
      # sender's own audience. A shared inbox has to resolve both, because
      # neither form mentions this instance.
      def audience_recipients(document, remote_actor)
        # `recipients` is Allure's explicit audience for computed sets (an
        # actor Delete addresses followers and every prior delivery recipient
        # after the relationship may already be gone).
        audience = %w[to cc bto bcc recipients].flat_map { |key| Array(document[key]) }.select { |value| value.is_a?(String) }
        return [] if audience.empty?

        (directly_addressed(audience) + follower_audience(audience, remote_actor)).uniq
      end

      def directly_addressed(audience)
        Actor.local.where(uri: audience).select { |actor| local_recipient?(actor) }
      end

      # Public and followers-only publications carry the author's audience, so
      # the receiver maps it onto its own accepted follows. Without this a shared
      # inbox answers 404 to every delivered publication.
      def follower_audience(audience, remote_actor)
        return [] unless audience.include?(PUBLIC_AUDIENCE) || audience.include?(followers_collection_uri(remote_actor))

        Following.accepted_followers_of(remote_actor).includes(:follower_actor)
          .filter_map { |following| following.follower_actor if local_recipient?(following.follower_actor) }
      end

      # Taken from the actor document rather than rebuilt from the actor URI: a
      # peer is free to host its followers collection anywhere, and Wanderer
      # already decouples handle domain from actor path.
      def followers_collection_uri(remote_actor)
        value = remote_actor.raw.is_a?(Hash) ? remote_actor.raw["followers"] : nil
        value if value.is_a?(String) && value.present?
      end

      def local_recipient?(actor)
        actor&.local? && !actor.tombstoned?
      end

      # An account deleting itself that this instance never knew has nothing
      # to take back here, and its key can no longer be fetched (its actor
      # answers 410). It is acknowledged without a fetch and without a row,
      # as Mastodon does, so a mass deletion costs no request.
      def unknown_actor_self_deletion?(envelope)
        return false unless envelope["type"] == "Delete"

        object = envelope["object"]
        object_id = object.is_a?(Hash) ? object["id"] : object
        object_id == envelope["actor"] && !Actor.exists?(uri: envelope["actor"])
      end

      # The signer is resolved without persisting: a request whose signature
      # does not verify must leave no actor row behind, otherwise any
      # unauthenticated POST naming a fresh actor URI writes a document-sized
      # row and the fetch it cost is never attributed to a verified authority.
      def persist_remote_actor!(actor)
        actor.save! if actor.new_record? || actor.changed?
      end

      def validate_signature_owner!(verification, actor, actor_uri)
        return if verification.key_id == actor.public_key_id && actor.uri == actor_uri

        raise InvalidRequest, "signature key does not belong to the claimed actor"
      end

      def admit_all!(recipients:, activity:)
        results = recipients.map { |recipient| admit!(recipient:, activity:) }
        AdmissionResult.new(results.map(&:first), results.all?(&:last))
      end

      def admit!(recipient:, activity:)
        digest = header_value("digest")
        item = FederationInboxItem.find_by(recipient_actor: recipient, activity_uri: activity.id)
        if item
          validate_duplicate!(item, digest:, activity:)
          return [ item, true ]
        end

        item = FederationInboxItem.create!(
          recipient_actor: recipient,
          activity_uri: activity.id,
          activity_type: activity.type,
          actor_uri: activity.actor,
          remote_domain: Allure::Federation::Authority.domain(activity.actor),
          raw_body_digest: digest,
          raw: activity.document
        )
        ProcessInboxItemJob.perform_later(item)
        [ item, false ]
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def validate_duplicate!(item, digest:, activity:)
        return if item.raw_body_digest == digest && item.actor_uri == activity.actor && item.activity_type == activity.type

        raise InvalidRequest, "activity URI was admitted with different content"
      end

      def header_value(name)
        @headers.find { |key, _value| key.to_s.casecmp?(name) }&.last.to_s
      end
    end
  end
end
