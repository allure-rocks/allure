# frozen_string_literal: true

module Participations
  # The participant turns a confirmed credit into a link by naming their own
  # recording of the same outing (PLAN_TOGETHER.md §5): the two workouts then
  # point at each other and the credit row is destroyed, so nothing is counted
  # twice. The participation stays confirmed, so the owner reads the new kind
  # on the card; no notice is sent.
  class Convert
    class NotAllowed < StandardError; end

    def initialize(participation:, user:, participant_workout:)
      @participation = participation
      @user = user
      @participant_workout = participant_workout
    end

    def call!
      raise NotAllowed, "not the participant" unless @participation.participant_actor.user_id == @user.id
      raise NotAllowed, "only a confirmed credit converts" unless @participation.confirmed? && @participation.kind == "credit"

      refusal = RecordingRules.refusal(participation: @participation, user: @user, recording: @participant_workout)
      raise NotAllowed, refusal if refusal

      WorkoutParticipation.transaction do
        credit_row = @participation.credit_row
        @participation.update!(kind: "link", participant_workout: @participant_workout, suggested_workout: nil)
        credit_row&.destroy!
      end
      Notifications::Withdraw.new(subject: @participation, kind: "participation_link_suggested").call!
      @participation
    end
  end
end
