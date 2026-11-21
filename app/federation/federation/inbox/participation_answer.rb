# frozen_string_literal: true

module Federation
  module Inbox
    # The answers and withdrawals of a remote participation
    # (docs/dev/SHARED-ACTIVITIES.md), each resolved from the Invite it names:
    #
    # - on the owner's instance, the invited account's `Accept` or `Reject` of
    #   the Invite, and its `Undo` of that `Accept`;
    # - on the invited account's instance, the owner's `Undo` of the Invite.
    #
    # Each method answers whether the activity was about a participation, so
    # the processor falls back to its follow and comment readings otherwise.
    # Only the party who sent the Invite, or the account it named, may act on
    # it; an answer to a closed participation changes nothing.
    class ParticipationAnswer
      def initialize(item:, activity:, now: Time.current)
        @item = item
        @activity = activity
        @now = now
      end

      def accept
        participation = invited_participation(object_uri(@activity["object"]))
        return false unless participation
        return true unless participation.active? && participation.participant_confirmed_at.nil?

        participation.update!(participant_confirmed_at: @now)
        Notifications::Create.new(user: participation.workout.user, kind: "participation_confirmed",
                                  actor: participation.participant_actor, subject: participation).call!
        Participations::SummaryRefresh.confirmed!(participation) if participation.confirmed?
        true
      end

      def reject
        participation = invited_participation(object_uri(@activity["object"]))
        return false unless participation
        return true unless participation.active? && participation.participant_confirmed_at.nil?

        participation.update!(declined_at: @now)
        Notifications::Withdraw.new(subject: participation).call!
        true
      end

      # The invited account takes back its confirmation: `Undo` of its
      # `Accept`, naming the Invite the Accept answered.
      def undo_accept
        object = @activity["object"]
        invite_uri = object.is_a?(Hash) ? object_uri(object["object"]) : nil
        participation = invited_participation(invite_uri)
        return false unless participation
        return true unless participation.active?

        participation.update!(withdrawn_at: @now)
        Notifications::Withdraw.new(subject: participation).call!
        Participations::SummaryRefresh.withdrawn!(participation)
        true
      end

      # The owner takes back its invitation: `Undo` of the Invite, received by
      # the account it named.
      def undo_invite
        participation = RemoteParticipation.find_by(invite_activity_uri: object_uri(@activity["object"]),
                                                    recipient_actor: @item.recipient_actor)
        return false unless participation
        raise Rejected, "only the inviting owner withdraws the invitation" unless participation.origin_actor&.uri == @item.actor_uri
        # A refusal stays the last word: undoing it would free the pair.
        return true unless participation.active?

        Participations::RemoteWithdrawal.withdraw!(participation, at: @now)
        true
      end

      private

      def invited_participation(invite_uri)
        return if invite_uri.blank?

        participation = WorkoutParticipation.find_by(wire_activity_uri: invite_uri)
        return unless participation
        raise Rejected, "only the invited account answers the invitation" unless participation.participant_actor.uri == @item.actor_uri

        participation
      end

      def object_uri(object) = object.is_a?(Hash) ? object["id"] : object
    end
  end
end
