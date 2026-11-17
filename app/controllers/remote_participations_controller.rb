# frozen_string_literal: true

# The invited account's answer to an invitation from another instance
# (docs/dev/SHARED-ACTIVITIES.md): confirm, decline, or withdraw a confirmation. Only
# that account finds the row; anyone else gets a 404.
class RemoteParticipationsController < ApplicationController
  NOTICES = {
    "confirm" => "workouts.participations.notices.confirmed",
    "decline" => "workouts.participations.notices.declined",
    "withdraw" => "workouts.participations.notices.withdrawn"
  }.freeze

  def update
    actor = current_user.actor
    raise ActiveRecord::RecordNotFound unless actor

    participation = RemoteParticipation.where(recipient_actor: actor).find_by_short_id!(params[:id])
    notice = NOTICES.fetch(params[:decision].to_s) { raise ActiveRecord::RecordNotFound }
    Participations::RemoteAnswer.new(participation:, user: current_user, decision: params[:decision]).call!
    redirect_to remote_note_path(participation.remote_note), notice: t(notice)
  rescue Participations::RemoteAnswer::NotAllowed
    redirect_to remote_note_path(participation.remote_note), alert: t("workouts.participations.notices.not_allowed")
  end
end
