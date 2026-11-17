# frozen_string_literal: true

module Notifications
  # One `reaction` notification per workout and owner
  # (docs/dev/NOTIFICATIONS.md). The row is always recomputed from the active reactions, never
  # incremented, so a withdrawal, a block, or a deleted account converges on
  # the same state: the newest counted reactor is the actor, and the payload
  # carries the total and the count per type. The row is locked before it is
  # recomputed, so concurrent reactions on one workout serialize and the last
  # recount sees every committed reaction.
  class ReactionDigest
    KIND = "reaction"

    # The digests a set of actors takes part in, by their active reactions on
    # local workouts.
    def self.refresh_for_actors!(actors)
      workout_ids = Reaction.active.where(actor: actors).where.not(workout_id: nil).distinct.pluck(:workout_id)
      Workout.where(id: workout_ids).includes(:user).find_each { |workout| new(workout:).refresh! }
    end

    def initialize(workout:)
      @workout = workout
    end

    # A new reaction: the digest is created if needed and, when `alert`, turns
    # unread again and moves to the top of the inbox. A switch of type by the
    # same account recounts without alerting.
    def record!(alert: true, now: Time.current)
      owner = @workout&.user
      return unless owner

      attributes = { user: owner, kind: KIND, subject: @workout }
      notification = Notification.find_by(attributes) || Notification.create_or_find_by!(attributes)
      fresh = notification.previously_new_record?
      notification.lock!
      apply!(notification, alert: alert || fresh, now:)
    end

    # A withdrawn reaction: the existing digest is recounted, and removed once
    # nothing is left to tell. A missing digest is never created here.
    def refresh!
      owner = @workout&.user
      return unless owner

      notification = Notification.lock.find_by(user: owner, kind: KIND, subject: @workout)
      return unless notification

      apply!(notification, alert: false, now: Time.current)
    end

    private

    def apply!(notification, alert:, now:)
      reactions = counted_reactions
      if reactions.empty?
        notification.destroy!
        return
      end

      attributes = {
        actor_id: reactions.first.actor_id,
        payload: { "count" => reactions.size, "kinds" => reactions.map(&:kind).tally }
      }
      attributes.merge!(read_at: nil, created_at: now) if alert
      notification.update!(attributes)
      # Only an alert reaches the devices (PLAN_PUSH.md §5): a silent recount
      # or a withdrawal pushes nothing.
      PushJob.enqueue_after_commit(notification) if alert
      notification
    end

    # Newest first. A deleted account and a blocked account no longer speak in
    # the owner's inbox; the owner's own actor never reacts to their workout.
    def counted_reactions
      reactions = Reaction.active.where(workout: @workout)
        .joins(:actor).where(actors: { tombstoned_at: nil })
        .where.not(actor_id: @workout.user.actor&.id)
        .includes(:actor)
        .order(created_at: :desc, id: :desc)
        .to_a
      reactions.reject { |reaction| reaction.actor.remote? && Federation::Safety::Blocks.blocked?(reaction.actor.uri) }
    end
  end
end
