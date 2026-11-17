# frozen_string_literal: true

# A received publication rendered in the established workout language. Remote
# copies are a signed-in surface; anonymous visitors never see them. A deleted
# note keeps a tombstone page for accounts that were entitled to it.
class RemoteNotesController < ApplicationController
  def show
    raise ActiveRecord::RecordNotFound unless Allure::Federation::Config.enabled?

    @note = RemoteNote.find(params[:id])
    return render_deleted if @note.deleted?

    @reaction_targets = [ @note ]

    @view = Federation::RemoteNoteView.new(@note)
    policy = Federation::RemoteNotePolicy.new(
      note: @note, principal: Workouts::PublicationPrincipal.browser(current_user)
    )
    raise ActiveRecord::RecordNotFound unless policy.allowed?(resource: :note)

    @chart_table = chart_table
    @remote_participation = remote_participation
    return if request.headers["Turbo-Frame"].blank?

    render partial: "remote_notes/media", locals: { note: @note, view: @view, chart_table: @chart_table }
  end

  private

  # An invitation from the note's owner to this account, pending or
  # confirmed (docs/dev/SHARED-ACTIVITIES.md); a refused one is closed for good.
  def remote_participation
    actor = current_user&.actor
    return unless actor

    RemoteParticipation.active.find_by(remote_note: @note, recipient_actor: actor)
  end

  def render_deleted
    raise ActiveRecord::RecordNotFound unless former_recipient?

    render :deleted
  end

  def former_recipient?
    actor = current_user&.actor
    return false unless actor

    @note.recipients.exists?(recipient_actor: actor)
  end

  def chart_table
    Array(@view.chart).filter_map do |point|
      next unless point.is_a?(Hash)

      {
        distance: point["distance"],
        elapsed_time: point["elapsed_time"],
        elevation: point["elevation"]
      }
    end
  end
end
