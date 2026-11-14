# frozen_string_literal: true

module Federation
  # PLAN_PEOPLE.md §5: the followed account ends one accepted follow. A local
  # follower is simply undone; a remote one gets the signed `Reject` of its
  # Follow, which is how ActivityPub software tells an account its follow no
  # longer stands. Nothing is recalled from the follower's instance: every
  # later signed object and media GET is reauthorized here against the live
  # follow, so the withdrawal is effective at the next read.
  class RemoveFollower
    class InvalidTarget < StandardError; end

    def initialize(following:, now: Time.current)
      @following = following
      @now = now
    end

    def call!
      validate!
      return undo_local! if @following.follower_actor.local?

      event = nil
      Following.transaction do
        @following.undo!(at: @now)
        event = FollowDecision.answer_event!(@following, "Reject")
      end
      Federation::ExpandOutboxEventJob.perform_later(event) if event.pending?
      @following
    end

    private

    def validate!
      raise InvalidTarget, "follow is not accepted" unless @following.accepted?
      raise InvalidTarget, "follow target is not local" unless @following.followed_actor.local?
      if @following.follower_actor.remote? && !Allure::Federation::Config.enabled?
        raise InvalidTarget, "federation is disabled"
      end
    end

    def undo_local!
      @following.undo!(at: @now)
      @following
    end
  end
end
