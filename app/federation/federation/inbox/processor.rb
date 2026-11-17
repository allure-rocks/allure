# frozen_string_literal: true

module Federation
  module Inbox
    class Processor
      class RejectedActivity < StandardError; end

      def initialize(item:, now: Time.current)
        @item = item
        @now = now
        @activity = @item.raw
        @outbox_events = []
        @media_attachments = []
      end

      attr_reader :outbox_events, :media_attachments

      def call!
        catch(:rejected) do
          reject!("actor is blocked") if Safety::Blocks.blocked?(@item.actor_uri)
          case @item.activity_type
          when "Follow" then process_follow
          when "Accept" then process_accept
          when "Reject" then process_reject
          when "Undo" then process_undo
          when "Like" then process_like
          when "Announce" then process_comment_relay
          when "Invite" then process_participation_invite
          when "Create" then process_object(:create)
          when "Delete" then process_object(:delete)
          when "Update" then reject!("Update is not supported; Delete then Create")
          else reject!("unsupported activity type")
          end
        end
      end

      private

      # Inbound follows are requests, not relationships: they stay pending
      # until the owner decides through Federation::FollowDecision.
      def process_follow
        reject!("follow target is not the recipient actor") unless @activity["object"] == @item.recipient_actor.uri
        remote_actor = remote_actor!
        reject!("actor is blocked") if Safety::Blocks.blocked?(remote_actor.uri)

        by_uri = Following.find_by(uri: @activity.fetch("id"))
        if by_uri && (by_uri.follower_actor_id != remote_actor.id || by_uri.followed_actor_id != @item.recipient_actor.id)
          raise RejectedActivity, "follow URI belongs to another actor pair"
        end

        following = by_uri || Following.active.find_by(follower_actor: remote_actor, followed_actor: @item.recipient_actor)
        following = if following.nil? || following.undone?
          Following.create!(follow_attributes(remote_actor))
        elsif following.rejected?
          # A new Follow is a new request; the unique active-relationship
          # constraint leaves no room for a second row.
          following.update!(follow_attributes(remote_actor))
          following
        else
          renew_follow!(following)
        end
        notify_follow_request!(remote_actor, following)
      end

      # A known relationship asked again under a new Follow id means the
      # follower lost it — it unfollowed while this instance could not hear
      # the Undo, or it was reset. The relationship takes the new id, so the
      # eventual Accept and a later Undo name what the follower holds, and an
      # accepted one is accepted again at once instead of waiting forever.
      def renew_follow!(following)
        return following if following.uri == @activity.fetch("id")

        following.update!(uri: @activity.fetch("id"), raw: @activity)
        @outbox_events << FollowDecision.answer_event!(following, "Accept") if following.accepted?
        following
      end

      # The recipient's inbox carries the request until it is decided; the
      # notification service keeps redelivery idempotent.
      def notify_follow_request!(remote_actor, following)
        return unless following.pending?

        Notifications::Create.new(
          user: @item.recipient_actor.user,
          kind: "follow_request",
          actor: remote_actor,
          subject: following
        ).call!
      end

      def follow_attributes(remote_actor)
        {
          follower_actor: remote_actor,
          followed_actor: @item.recipient_actor,
          uri: @activity.fetch("id"),
          status: "pending",
          requested_at: @now,
          raw: @activity
        }
      end

      def process_reject
        following = Following.find_by(uri: activity_object_id)
        return if !following && participation_answered?(:reject)
        return process_comment_refusal unless following
        reject!("reject actor does not match followed actor") unless following.followed_actor.uri == @item.actor_uri
        return if following.undone? || following.rejected?

        # A pending request is refused; an accepted one is the owner removing
        # this follower (Mastodon sends Reject(Follow)), which ends it.
        following.pending? ? following.reject!(at: @now) : following.undo!(at: @now)
        withdraw_entitlements!(following)
        # The owner refused this account's follow: its invitations from that
        # owner end, and a confirmation taken back is told (docs/dev/SHARED-ACTIVITIES.md).
        if following.follower_actor.local?
          @outbox_events.concat(Participations::RemoteWithdrawal.for_pair!(
            recipient_actor: following.follower_actor, origin_actor: following.followed_actor,
            at: @now, notify_origin: true
          ))
        end
      end

      # A rejection after earlier delivery withdraws the local follower's
      # copies immediately; a followers-only object is purged (docs/dev/FEDERATION.md).
      def withdraw_entitlements!(following)
        local_actor = following.follower_actor
        remote_actor = following.followed_actor
        return unless local_actor.local?

        [ RemoteNote, RemoteSegment ].each do |model|
          model.where(actor: remote_actor).find_each do |record|
            record.recipients.active.where(recipient_actor: local_actor).find_each do |recipient|
              recipient.withdraw!(reason: "rejected", at: @now)
            end
            RemoteMedia::Purge.new(owner: record, now: @now).call!
          end
        end
      end

      def process_accept
        following = Following.find_by(uri: activity_object_id)
        return if !following && participation_answered?(:accept)
        reject!("accept references an unknown follow") unless following
        reject!("accept actor does not match followed actor") unless following.followed_actor.uri == @item.actor_uri
        return unless following.pending?

        following.accept!
        notify_follow_accepted!(following) if following.follower_actor.local?
      end

      def notify_follow_accepted!(following)
        Notifications::Create.new(
          user: following.follower_actor.user,
          kind: "follow_accepted",
          actor: following.followed_actor,
          subject: following
        ).call!
      end

      # A withdrawn request no longer needs a decision, so its inbox entry
      # goes with it.
      def withdraw_follow_request!(following)
        followed = following.followed_actor
        return unless followed.local? && followed.user

        Notifications::Withdraw.new(
          user: followed.user,
          subject: following,
          kind: "follow_request"
        ).call!
      end

      def process_undo
        object = @activity["object"]
        object_type = object.is_a?(Hash) ? object["type"] : nil
        object_uri = object.is_a?(Hash) ? object["id"] : object
        case object_type
        when nil, "Follow"
          following = Following.find_by(uri: object_uri)
          reject!("undo references an unknown follow") unless following
          reject!("undo actor does not match follower") unless following.follower_actor.uri == @item.actor_uri
          following.undo!(at: @now)
          withdraw_follow_request!(following)
          Participations::RemoteWithdrawal.participant_left!(
            owner_actor: following.followed_actor, participant_actor: following.follower_actor, at: @now
          )
        when "Like"
          reaction = Reaction.find_by(uri: object_uri)
          reject!("undo references an unknown like") unless reaction
          reject!("undo actor does not match liker") unless reaction.actor.uri == @item.actor_uri
          reaction.undo!(at: @now)
          withdraw_reaction_notification!(reaction)
        when "Announce"
          process_comment_relay_undo
        when "Accept"
          reject!("undo references an unknown accept") unless participation_answered?(:undo_accept)
        when "Invite"
          reject!("undo references an unknown invitation") unless participation_answered?(:undo_invite)
        else
          reject!("unsupported undo object")
        end
      end

      def process_like
        publication = WorkoutPublication.active.find_by(object_uri: @activity["object"])
        reject!("like target is unknown") unless publication
        remote_actor = remote_actor!
        policy = Workouts::PublicationPolicy.new(
          publication:,
          principal: Workouts::PublicationPrincipal.protocol(remote_actor)
        )
        reject!("actor is not allowed to like this publication") unless policy.allowed?(resource: :like)
        reaction = Reaction.find_by(uri: @activity.fetch("id"))
        if reaction && (reaction.actor_id != remote_actor.id || reaction.workout_id != publication.workout_id)
          raise RejectedActivity, "like URI belongs to another actor pair"
        end
        reaction ||= Reaction.active.find_by(actor: remote_actor, workout: publication.workout)
        return if reaction

        reaction = Reaction.create!(
          actor: remote_actor,
          workout: publication.workout,
          uri: @activity.fetch("id"),
          kind: reaction_kind,
          audience: publication.audience
        )
        notify_reaction!(reaction)
      end

      # The Allure reaction type travels in the private `_allure_reaction`
      # property; an external peer that sends a plain Like (or an unknown
      # value) means the neutral type, exactly like the missing property
      # (PLAN_REACTIONS.md §4.3).
      def reaction_kind
        kind = @activity["_allure_reaction"].to_s
        Reaction::KINDS.include?(kind) ? kind : Reaction::DEFAULT_KIND
      end

      def notify_reaction!(reaction)
        Notifications::Create.new(
          user: reaction.workout.user,
          kind: "reaction",
          actor: reaction.actor,
          subject: reaction
        ).call!
      end

      def withdraw_reaction_notification!(reaction)
        owner = reaction.workout&.user
        return unless owner

        Notifications::Withdraw.new(
          user: owner,
          kind: "reaction",
          subject: reaction
        ).call!
      end

      # Object activities are handled by dedicated handlers that route by the
      # embedded object path (workout trail vs course); their terminal
      # validation failures reject the item without retrying. Pending media is
      # collected for the job to enqueue after commit, so no fetch can start
      # before the descriptor row is durable. A Create answering something
      # through `inReplyTo` is a comment (PLAN_COMMENTS.md §7.2).
      def process_object(kind)
        return process_comment if kind == :create && comment_create?

        result = if kind == :create
          Inbox::Create.new(item: @item, activity: @activity, now: @now).call!
        else
          Inbox::Delete.new(item: @item, activity: @activity, now: @now, outbox_events: @outbox_events).call!
        end
        @media_attachments.concat(result.attachments.pending.to_a) if kind == :create && result.respond_to?(:attachments)
        result
      rescue Inbox::Rejected => error
        reject!(error.message)
      end

      def comment_create?
        object = @activity["object"]
        object.is_a?(Hash) && object["inReplyTo"].present?
      end

      # A refusal still owes the author its Reject: the handler queues it on
      # the outbox events this transaction commits.
      def process_comment
        Inbox::CommentReceipt.new(item: @item, activity: @activity, outbox_events: @outbox_events, now: @now).call!
      rescue Inbox::Rejected => error
        reject!(error.message)
      end

      # A thread host relays a comment on its public publication, or stops
      # relaying it (PLAN_COMMENTS.md §7.5). A fetch the author's instance could
      # not answer yet raises and the item retries with the usual backoff.
      def process_comment_relay
        Inbox::CommentRelay.new(item: @item, activity: @activity, now: @now).call!
      rescue Inbox::Rejected => error
        reject!(error.message)
      end

      # A remote owner invites a local account to confirm it took part in a
      # publication it holds (docs/dev/SHARED-ACTIVITIES.md).
      def process_participation_invite
        Inbox::ParticipationInvite.new(item: @item, activity: @activity, now: @now).call!
      rescue Inbox::Rejected => error
        reject!(error.message)
      end

      # An answer to, or a withdrawal of, a remote participation
      # (docs/dev/SHARED-ACTIVITIES.md); false when the activity names none.
      def participation_answered?(step)
        Inbox::ParticipationAnswer.new(item: @item, activity: @activity, now: @now).public_send(step)
      rescue Inbox::Rejected => error
        reject!(error.message)
      end

      def process_comment_relay_undo
        Inbox::CommentRelayUndo.new(item: @item, activity: @activity, now: @now).call!
      rescue Inbox::Rejected => error
        reject!(error.message)
      end

      # The thread host refused or took out a comment written here
      # (PLAN_COMMENTS.md §7.4).
      def process_comment_refusal
        Inbox::CommentRefusal.new(item: @item, activity: @activity, now: @now).call!
      rescue Inbox::Rejected => error
        reject!(error.message)
      end

      def remote_actor!
        actor = Actor.find_by(uri: @item.actor_uri)
        raise RejectedActivity, "remote actor is not cached" unless actor&.remote? && !actor.tombstoned?

        actor
      end

      def activity_object_id
        object = @activity["object"]
        object.is_a?(Hash) ? object["id"] : object
      end

      def reject!(reason)
        @item.reject!(reason:, at: @now)
        throw :rejected, @item
      end
    end
  end
end
