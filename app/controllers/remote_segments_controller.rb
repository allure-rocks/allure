# frozen_string_literal: true

# The remote course page. A public course is readable by any signed-in
# account; a followers-only course requires an active entitlement; a deleted
# course renders a tombstone for former recipients only
# (PLAN_SEGMENTS_FEDERATION.md §12.2).
class RemoteSegmentsController < ApplicationController
  def show
    raise ActiveRecord::RecordNotFound unless Allure::Federation::Config.enabled?

    @segment = RemoteSegment.find(params[:id])
    return render_deleted if @segment.deleted?

    @view = Federation::RemoteSegmentView.new(@segment)
    policy = Federation::RemoteSegmentPolicy.new(
      segment: @segment, principal: Workouts::PublicationPrincipal.browser(current_user)
    )
    raise ActiveRecord::RecordNotFound unless policy.allowed?(resource: :segment)

    return if request.headers["Turbo-Frame"].blank?

    render partial: "remote_segments/media", locals: { segment: @segment, view: @view }
  end

  private

  def render_deleted
    raise ActiveRecord::RecordNotFound unless former_recipient?

    render :deleted
  end

  def former_recipient?
    return false unless current_user&.actor

    @segment.recipients.exists?(recipient_actor: current_user.actor)
  end
end
