# frozen_string_literal: true

require "digest"
require "securerandom"

module Federation
  # Follows a local account (pending the target's approval, never federated) or
  # a remote actor (pending until the peer accepts, with a durable Follow
  # intent).
  class Follow
    class InvalidTarget < StandardError; end

    def initialize(user:, target:, actor_resolver: nil, webfinger_resolver: nil, config: Allure::Federation.config)
      @user = user
      @target = target.to_s.strip
      @config = config
      @target_resolver = TargetResolver.new(actor_resolver:, webfinger_resolver:, config:)
    end

    def call!
      # Local relationships never use the wire protocol (the unfederated demo
      # seeds them too). Refuse a remote target before resolving it, so disabling
      # federation still prevents every outbound discovery request.
      unless Allure::Federation::Config.enabled? || @target_resolver.local_target?(@target)
        raise InvalidTarget, "federation is disabled"
      end

      local_actor = Federation::ActorProvisioner.new(user: @user, config: @config).call!
      target_actor = @target_resolver.call!(@target)
      return follow_remote!(local_actor, target_actor) unless target_actor.local?

      following = follow_local!(local_actor, target_actor)
      notify_local_request!(local_actor, following)
      following
    rescue TargetResolver::InvalidTarget => error
      raise InvalidTarget, error.message
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    private

    # The target's inbox carries the request until it is decided; the unique
    # index keeps a re-ask idempotent and a decided request from resurfacing.
    def notify_local_request!(local_actor, following)
      return unless following.pending?

      Notifications::Create.new(
        user: following.followed_actor.user,
        kind: "follow_request",
        actor: local_actor,
        subject: following
      ).call!
    end

    # A local request is decided by the target on /people and never leaves the
    # instance: no outbox event, no signed Accept/Reject. Re-requesting after a
    # rejection resets the same row to pending, exactly like an inbound remote
    # Follow.
    def follow_local!(local_actor, target_actor)
      raise InvalidTarget, "you cannot follow yourself" if local_actor.id == target_actor.id

      following = Following.active.find_by(follower_actor: local_actor, followed_actor: target_actor)
      if following
        following.update!(status: "pending", requested_at: Time.current) if following.rejected?
        return following
      end

      Following.create!(
        follower_actor: local_actor,
        followed_actor: target_actor,
        uri: local_follow_uri(local_actor, target_actor),
        status: "pending",
        requested_at: Time.current
      )
    end

    def follow_remote!(local_actor, remote_actor)
      existing = Following.active.find_by(follower_actor: local_actor, followed_actor: remote_actor)
      if existing
        event = ensure_follow_event!(existing, local_actor, remote_actor)
        if event.terminal? || existing.rejected?
          # Retry after a terminal delivery failure, or ask again after a
          # refusal: a new Follow identity, one pending relationship. A
          # refused row left as is would ignore the Accept that answers it.
          event = build_follow_event!(
            local_actor, remote_actor,
            idempotency_key: follow_idempotency_key(remote_actor)
          )
          existing.update!(uri: event.activity_uri, status: "pending", requested_at: Time.current)
        end
        enqueue_expansion(event)
        return existing
      end

      event = nil
      following = Following.transaction do
        event = build_follow_event!(local_actor, remote_actor, idempotency_key: follow_idempotency_key(remote_actor))
        Following.create!(
          follower_actor: local_actor,
          followed_actor: remote_actor,
          uri: event.activity_uri,
          requested_at: Time.current
        )
      end
      enqueue_expansion(event)
      following
    end

    # A local relationship has no ActivityPub identity and is never delivered.
    # The URI only needs to be absolute and unique per attempt: re-following
    # after an undo creates a new row.
    def local_follow_uri(local_actor, target_actor)
      digest = Digest::SHA256.hexdigest("#{local_actor.id}:#{target_actor.id}:#{SecureRandom.uuid}")[0, 32]
      "#{@config.base_url}/local_follows/#{digest}"
    end

    def ensure_follow_event!(following, local_actor, remote_actor)
      existing_event = FederationOutboxEvent.find_by(activity_uri: following.uri)
      return existing_event if existing_event

      build_follow_event!(local_actor, remote_actor, idempotency_key: follow_idempotency_key(remote_actor)).tap do |event|
        following.update!(uri: event.activity_uri)
      end
    end

    def build_follow_event!(local_actor, remote_actor, idempotency_key:)
      activity_uri = Federation::Outbox::EventBuilder.activity_uri_for(
        object_uri: local_actor.uri, activity_type: "Follow", idempotency_key:
      )
      Federation::Outbox::EventBuilder.new(
        actor: local_actor,
        subject_type: "Actor",
        subject_id: local_actor.id,
        activity_type: "Follow",
        object_uri: local_actor.uri,
        idempotency_key:,
        payload: {
          "type" => "Follow",
          "actor" => local_actor.uri,
          "object" => remote_actor.uri,
          "id" => activity_uri
        },
        audience: { "to" => [ remote_actor.uri ], "cc" => [] }
      ).call!
    end

    # Random from the first Follow: a URI derived from the two actors could
    # be computed by anyone and used to probe the social graph (docs/dev/FEDERATION.md
    # §12.6). Idempotency rests on the active relationship, not on the URI.
    def follow_idempotency_key(remote_actor) = "follow:#{remote_actor.uri}:#{SecureRandom.uuid}"

    def enqueue_expansion(event)
      return unless event&.pending?

      Federation::ExpandOutboxEventJob.perform_later(event)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name })
    end
  end
end
