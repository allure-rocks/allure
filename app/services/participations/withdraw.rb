# frozen_string_literal: true

module Participations
  # Either party ends a live participation (PLAN_TOGETHER.md §5). Withdrawal is
  # the privacy consequence: open notifications disappear, and the attached
  # credit row is destroyed, its destroy hooks recomputing the participant's
  # records. A remote participant's instance hears of it through an `Undo` of
  # the Invite (§7), expanded after commit.
  class Withdraw
    class NotAllowed < StandardError; end

    def initialize(participation:, user:)
      @participation = participation
      @user = user
    end

    def call!
      raise NotAllowed, "the participation is closed" unless @participation.active?
      raise NotAllowed, "not a party to the participation" unless party?

      event = nil
      WorkoutParticipation.transaction do
        credit_row = @participation.credit_row
        @participation.update!(withdrawn_at: Time.current)
        credit_row&.destroy!
        if @participation.wire_activity_uri.present?
          event = Federation::Outbox::ParticipationUndoInvite.new(participation: @participation).call!
        end
      end
      Notifications::Withdraw.new(subject: @participation).call!
      Comments::Outbound.enqueue!(event)
      @participation
    end

    private

    def party?
      @participation.workout.user_id == @user.id ||
        @participation.participant_actor.user_id == @user.id
    end
  end
end
