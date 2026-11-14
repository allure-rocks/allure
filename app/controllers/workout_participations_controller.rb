# frozen_string_literal: true

# The local shared-activity gestures (PLAN_TOGETHER.md §5, §8): the owner
# invites, the participant confirms or declines (both sides answer a
# detection), and either party withdraws. A detection counterpart answers
# from their own recording, so answers return to the page they came from.
# Every
# transition goes through its service; the controller resolves the
# workout-scoped row, answers 404 to anyone else (denial is never 403), and
# turns a business refusal into a localized flash.
class WorkoutParticipationsController < ApplicationController
  DECISION_NOTICES = {
    "confirm" => "workouts.participations.notices.confirmed",
    "decline" => "workouts.participations.notices.declined"
  }.freeze

  before_action :set_workout
  before_action :authorize_owner, only: :create
  before_action :authorize_decider, only: :update
  before_action :authorize_participant, only: %i[convert dismiss_link_suggestion]
  before_action :authorize_party, only: :destroy

  def create
    Participations::Propose.new(
      user: current_user,
      workout: @workout,
      target: participation_params[:handle]
    ).call!
    redirect_to workout_path(@workout), notice: t("workouts.participations.notices.proposed")
  rescue Participations::Propose::NotAllowed
    # A remote account has conditions of its own (PLAN_TOGETHER.md §7).
    remote = !Federation::TargetResolver.new.local_target?(participation_params[:handle])
    redirect_to workout_path(@workout),
                alert: t(remote ? "workouts.participations.notices.not_allowed_remote" : "workouts.participations.notices.not_allowed")
  end

  def update
    notice_key = DECISION_NOTICES.fetch(params[:decision].to_s, nil)
    raise ActiveRecord::RecordNotFound unless notice_key

    Participations::Decide.new(
      participation: @participation,
      user: current_user,
      decision: params[:decision],
      participant_workout: (recording if params[:decision].to_s == "confirm")
    ).call!
    redirect_back_or_to workout_path(@workout), notice: t(notice_key)
  rescue Participations::Decide::NotAllowed
    redirect_back_or_to workout_path(@workout), alert: t("workouts.participations.notices.not_allowed")
  end

  def convert
    workout = recording
    raise ActiveRecord::RecordNotFound unless workout

    Participations::Convert.new(participation: @participation, user: current_user, participant_workout: workout).call!
    # The credit row is gone; the participant's own recording now carries the link.
    redirect_to workout_path(workout), notice: t("workouts.participations.notices.converted")
  rescue Participations::Convert::NotAllowed
    redirect_to workout_path(@workout), alert: t("workouts.participations.notices.not_allowed")
  end

  # The participant keeps the credit: the suggestion of linking a recording
  # closes for good (PLAN_TOGETHER.md §8).
  def dismiss_link_suggestion
    if @participation.link_suggestion_open?
      @participation.update!(link_suggestion_dismissed_at: Time.current)
      Notifications::Withdraw.new(subject: @participation, kind: "participation_link_suggested").call!
    end
    redirect_back_or_to workout_path(@workout), notice: t("workouts.participations.notices.suggestion_dismissed")
  end

  def destroy
    Participations::Withdraw.new(participation: @participation, user: current_user).call!
    redirect_back_or_to workout_path(@workout), notice: t("workouts.participations.notices.withdrawn")
  rescue Participations::Withdraw::NotAllowed
    redirect_back_or_to workout_path(@workout), alert: t("workouts.participations.notices.not_allowed")
  end

  private

  def set_workout
    @workout = Workout.find_by_short_id!(params[:workout_id])
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  def authorize_owner
    raise ActiveRecord::RecordNotFound unless @workout.user_id == current_user.id
  end

  # The participant answers; the source owner also answers a detection.
  def authorize_decider
    @participation = find_participation
    return if @participation.participant_actor.user_id == current_user.id
    return if @participation.origin == "detection" && @workout.user_id == current_user.id

    raise ActiveRecord::RecordNotFound
  end

  def authorize_participant
    @participation = find_participation
    raise ActiveRecord::RecordNotFound unless @participation.participant_actor.user_id == current_user.id
  end

  def authorize_party
    @participation = find_participation
    return if @participation.workout.user_id == current_user.id
    return if @participation.participant_actor.user_id == current_user.id

    raise ActiveRecord::RecordNotFound
  end

  def find_participation
    @workout.workout_participations.find(params[:id])
  end

  def participation_params
    params.fetch(:participation, {}).permit(:handle)
  end

  # The participant's own recording named in the picker; blank means none.
  # Another account's workout is never found, so it cannot be named.
  def recording
    id = params[:participant_workout_id].presence
    return unless id

    current_user.workouts.find_by_short_id!(id)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
