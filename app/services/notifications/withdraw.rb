# frozen_string_literal: true

module Notifications
  # Removes notifications whose relationship ended: a decided follow request, an
  # undone follow, a blocked actor, or a deleted remote actor. Withdrawal is the
  # privacy consequence, so it is unconditional and never announced.
  #
  # A reaction digest speaks for every account that reacted to a workout
  # (PLAN_NOTIFICATIONS.md §8), so it is recounted instead of deleted: a
  # withdrawn reaction or an actor-wide withdrawal leaves the other accounts'
  # reactions in it.
  class Withdraw
    def initialize(user: nil, subject: nil, actor: nil, kind: nil)
      @user = user
      @subject = subject
      @actor = actor
      @kind = kind
    end

    def call!
      return refresh_reaction_digest! if @subject.is_a?(Reaction)

      if @actor
        scope.where.not(kind: ReactionDigest::KIND).delete_all
        ReactionDigest.refresh_for_actors!(@actor) if @kind.nil? || @kind.to_s == ReactionDigest::KIND
      else
        scope.delete_all
      end
    end

    private

    def refresh_reaction_digest!
      workout = @subject.workout
      return if workout.nil? || (@user && workout.user_id != @user.id)

      ReactionDigest.new(workout:).refresh!
    end

    def scope
      relation = Notification.all
      relation = relation.where(user: @user) if @user
      relation = relation.where(subject: @subject) if @subject
      relation = relation.where(actor: @actor) if @actor
      relation = relation.where(kind: @kind) if @kind
      relation
    end
  end
end
