# frozen_string_literal: true

module Participations
  # A local account's answer to an invitation from another instance
  # (PLAN_TOGETHER.md §7): confirm or decline while it is pending, sending
  # the owner an `Accept` or a `Reject` of the Invite, or later withdraw a
  # confirmation with an `Undo` of that `Accept`. A refusal is terminal. The
  # answer commits with its outbox intent; expansion runs after commit.
  class RemoteAnswer
    class NotAllowed < StandardError; end

    DECISIONS = %w[confirm decline withdraw].freeze

    def initialize(participation:, user:, decision:, now: Time.current)
      @participation = participation
      @user = user
      @decision = decision.to_s
      @now = now
    end

    def call!
      raise NotAllowed, "not the invited account" unless @participation.recipient_actor.user_id == @user.id
      raise NotAllowed, "unknown decision" unless DECISIONS.include?(@decision)

      event = @decision == "withdraw" ? withdraw : answer
      Comments::Outbound.enqueue!(event)
      @participation
    end

    private

    def answer
      RemoteParticipation.transaction do
        # Locked, so a double submission answers once.
        @participation.lock!
        raise NotAllowed, "the invitation is closed" unless @participation.pending?
        raise NotAllowed, "the publication is gone" unless @participation.remote_note&.active?

        if @decision == "confirm"
          @participation.update!(confirmed_at: @now)
          Notifications::Withdraw.new(subject: @participation, kind: "participation_requested").call!
          # A confirmation counts for the account at once, or not at all
          # (§7.5): the credit row commits with it.
          RemoteCreditRows.attach(@participation)
        else
          @participation.update!(declined_at: @now)
          Notifications::Withdraw.new(subject: @participation).call!
        end
        Federation::Outbox::ParticipationAnswer.new(participation: @participation)
          .answer!(@decision == "confirm" ? "Accept" : "Reject")
      end
    end

    def withdraw
      raise NotAllowed, "only a confirmation is withdrawn" unless @participation.confirmed?

      RemoteWithdrawal.withdraw!(@participation, at: @now, notify_origin: true)
    end
  end
end
