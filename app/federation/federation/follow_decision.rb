# frozen_string_literal: true

module Federation
  # Accepts or rejects one pending follow request. A remote follower gets a
  # signed Accept or Reject; a local follower only changes state, because a
  # local relationship has no wire identity. The owner of the followed local
  # actor performs the decision; authorization lives in the controller.
  class FollowDecision
    class InvalidDecision < StandardError; end

    DECISIONS = %w[accept reject].freeze

    def initialize(following:, decision:, now: Time.current)
      @following = following
      @decision = decision.to_s
      @now = now
    end

    def call!
      validate!
      if @following.follower_actor.local?
        decide_local!
      else
        decide_remote!
      end
      reconcile_notifications!
      @following
    end

    # The signed Accept or Reject of a remote follower's Follow, named by the
    # Follow id the relationship currently holds.
    def self.answer_event!(following, type)
      local_actor = following.followed_actor
      follower = following.follower_actor
      idempotency_key = "#{type.downcase}:#{following.uri}"
      activity_uri = Federation::Outbox::EventBuilder.activity_uri_for(
        object_uri: local_actor.uri, activity_type: type, idempotency_key:
      )
      Federation::Outbox::EventBuilder.new(
        actor: local_actor,
        subject_type: "Actor",
        subject_id: local_actor.id,
        activity_type: type,
        object_uri: local_actor.uri,
        idempotency_key:,
        payload: {
          "type" => type,
          "actor" => local_actor.uri,
          "object" => following.uri,
          "id" => activity_uri
        },
        audience: { "to" => [ follower.uri ], "cc" => [] }
      ).call!
    end

    private

    # The decision resolves the followed account's request inbox entry; an
    # accepted local request also tells the follower their request succeeded.
    def reconcile_notifications!
      Notifications::Withdraw.new(
        user: @following.followed_actor.user,
        subject: @following,
        kind: "follow_request"
      ).call!
      return unless @following.accepted? && @following.follower_actor.local?

      Notifications::Create.new(
        user: @following.follower_actor.user,
        kind: "follow_accepted",
        actor: @following.followed_actor,
        subject: @following
      ).call!
    end

    def validate!
      raise InvalidDecision, "unknown decision" unless DECISIONS.include?(@decision)
      raise InvalidDecision, "follow is not pending" unless @following.pending?
      raise InvalidDecision, "follow target is not local" unless @following.followed_actor.local?
      if @following.follower_actor.remote? && !Allure::Federation::Config.enabled?
        raise InvalidDecision, "federation is disabled"
      end
      return unless @following.follower_actor.remote? && @decision == "accept"
      raise InvalidDecision, "follower is blocked" if Safety::Blocks.blocked?(@following.follower_actor.uri)
    end

    # A local request has no wire identity: the state change is the whole
    # decision, and no Accept/Reject is emitted.
    def decide_local!
      @following.with_lock do
        @decision == "accept" ? @following.accept!(at: @now) : @following.reject!(at: @now)
      end
    end

    def decide_remote!
      event = nil
      Following.transaction do
        @following.with_lock do
          if @decision == "accept"
            @following.accept!(at: @now)
            event = create_event!("Accept")
          else
            @following.reject!(at: @now)
            event = create_event!("Reject")
          end
        end
      end
      enqueue(event)
    end

    def create_event!(type) = self.class.answer_event!(@following, type)

    def enqueue(event)
      return unless event&.pending?

      Federation::ExpandOutboxEventJob.perform_later(event)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, following_id: @following.id })
    end
  end
end
