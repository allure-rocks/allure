# frozen_string_literal: true

module Federation
  # Withdraws a local or remote follow. A remote follow emits Undo(Follow); a
  # local relationship is simply undone.
  class Unfollow
    class InvalidTarget < StandardError; end

    def initialize(user:, target:, actor_resolver: nil, webfinger_resolver: nil, config: Allure::Federation.config)
      @user = user
      @target = target.to_s.strip
      @config = config
      @target_resolver = TargetResolver.new(actor_resolver:, webfinger_resolver:, config:)
    end

    def call!
      # As in Follow: a local relationship is undone whatever the switch says,
      # a remote one is refused before any request while federation is off.
      unless Allure::Federation::Config.enabled? || @target_resolver.local_target?(@target)
        raise InvalidTarget, "federation is disabled"
      end

      local_actor = Federation::ActorProvisioner.new(user: @user, config: @config).call!
      following = stored_following(local_actor) || resolved_following(local_actor)
      raise InvalidTarget, "not following this account" unless following

      target_actor = following.followed_actor

      if target_actor.local?
        following.undo!
        withdraw_follow_request!(following)
        return following
      end

      event = nil
      participation_events = []
      Following.transaction do
        following.undo!
        withdraw_entitlements!(local_actor, target_actor)
        # Invitations from this owner end with the relationship; a
        # confirmation taken back is told (docs/dev/SHARED-ACTIVITIES.md).
        participation_events = Participations::RemoteWithdrawal.for_pair!(
          recipient_actor: local_actor, origin_actor: target_actor, notify_origin: true
        )
        event = create_undo_event!(following, local_actor, target_actor)
      end
      Federation::ExpandOutboxEventJob.perform_later(event) if event.pending?
      Comments::Outbound.enqueue!(participation_events)
      following
    rescue TargetResolver::InvalidTarget => error
      raise InvalidTarget, error.message
    end

    private

    # The relationship already names the remote actor, so a target matching
    # its stored URI, acct or handle is undone without any request: an
    # instance that no longer answers, or an author it deleted, can still be
    # unfollowed.
    def stored_following(local_actor)
      return if @target.blank? || @target_resolver.local_target?(@target)

      handle = @target.sub(/\A@/, "").sub(/\Aacct:/i, "").downcase
      scope = Following.active.where(follower_actor: local_actor).joins(:followed_actor).where(actors: { local: false })
      scope.where(actors: { uri: @target })
        .or(scope.where("LOWER(actors.acct) = :handle OR LOWER(LTRIM(actors.handle, '@')) = :handle", handle:))
        .order(:id)
        .first
    end

    def resolved_following(local_actor)
      target_actor = @target_resolver.call!(@target)
      Following.active.find_by(follower_actor: local_actor, followed_actor: target_actor)
    end

    # A withdrawn local request no longer needs the target's decision, so its
    # inbox entry goes with it.
    def withdraw_follow_request!(following)
      Notifications::Withdraw.new(
        user: following.followed_actor.user,
        subject: following,
        kind: "follow_request"
      ).call!
    end

    # Delivered copies of this author disappear from the feed and profile lists
    # immediately. Public media is retained; a followers-only object is purged
    # once its last entitlement is withdrawn (docs/dev/FEDERATION.md).
    def withdraw_entitlements!(local_actor, remote_actor)
      [ RemoteNote, RemoteSegment ].each do |model|
        model.where(actor: remote_actor).find_each do |record|
          record.recipients.active.where(recipient_actor: local_actor).find_each do |recipient|
            recipient.withdraw!(reason: "unfollow")
          end
          RemoteMedia::Purge.new(owner: record).call!
        end
      end
    end

    def create_undo_event!(following, local_actor, remote_actor)
      key = "undo-follow:#{following.uri}"
      activity_uri = Federation::Outbox::EventBuilder.activity_uri_for(
        object_uri: local_actor.uri, activity_type: "Undo", idempotency_key: key
      )
      Federation::Outbox::EventBuilder.new(
        actor: local_actor,
        subject_type: "Actor",
        subject_id: local_actor.id,
        activity_type: "Undo",
        object_uri: local_actor.uri,
        idempotency_key: key,
        payload: {
          "type" => "Undo",
          "actor" => local_actor.uri,
          "object" => { "type" => "Follow", "id" => following.uri },
          "id" => activity_uri
        },
        audience: { "to" => [ remote_actor.uri ], "cc" => [] }
      ).call!
    end
  end
end
