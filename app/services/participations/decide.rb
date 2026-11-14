# frozen_string_literal: true

module Participations
  # An answer to a participation (PLAN_TOGETHER.md §5, §8). For an invitation
  # the participant answers: confirming records the second confirmation, and
  # may turn the proposed credit into a link by naming their own recording.
  # For a detection both accounts answer, each for their own side; each
  # confirmation tells the other side, and the link holds once both agreed.
  # Declining, by either side, is terminal for the pair and removes the
  # participation's notices.
  class Decide
    class NotAllowed < StandardError; end

    DECISIONS = %w[confirm decline].freeze

    def initialize(participation:, user:, decision:, participant_workout: nil)
      @participation = participation
      @user = user
      @decision = decision.to_s
      @participant_workout = participant_workout
    end

    def call!
      side = side_of_user
      raise NotAllowed, "not a party to this answer" unless side
      raise NotAllowed, "the participation is closed" unless @participation.active?
      raise NotAllowed, "already confirmed" if confirmed_by?(side)
      raise NotAllowed, "unknown decision" unless DECISIONS.include?(@decision)

      @decision == "confirm" ? confirm(side) : decline
    end

    private

    # The participant answers every participation; the source owner answers a
    # detection, which nobody proposed.
    def side_of_user
      return :participant if @participation.participant_actor.user_id == @user.id
      return :owner if @participation.origin == "detection" && @participation.workout.user_id == @user.id

      nil
    end

    def confirmed_by?(side)
      side == :owner ? @participation.owner_confirmed_at.present? : @participation.participant_confirmed_at.present?
    end

    def confirm(side)
      attributes = side == :owner ? { owner_confirmed_at: Time.current } : { participant_confirmed_at: Time.current }
      if @participant_workout && side == :participant && @participation.kind == "credit"
        refusal = RecordingRules.refusal(participation: @participation, user: @user, recording: @participant_workout)
        raise NotAllowed, refusal if refusal

        attributes[:kind] = "link"
        attributes[:participant_workout] = @participant_workout
      end
      @participation.update!(attributes)
      Notifications::Withdraw.new(user: @user, subject: @participation, kind: "participation_suggested").call!
      notify_other_side(side)
      # A confirmed credit gets its credit row (PLAN_TOGETHER.md §6.2).
      CreditJob.perform_later(@participation) if @participation.kind == "credit"
      @participation
    end

    def decline
      @participation.update!(declined_at: Time.current)
      Notifications::Withdraw.new(subject: @participation).call!
      @participation
    end

    def notify_other_side(side)
      recipient, actor = if side == :owner
        [ @participation.participant_user, @participation.workout.user.actor ]
      else
        [ @participation.workout.user, @participation.participant_actor ]
      end
      Notifications::Create.new(user: recipient, kind: "participation_confirmed", actor:, subject: @participation).call!
    end
  end
end
