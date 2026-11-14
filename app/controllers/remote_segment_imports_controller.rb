# frozen_string_literal: true

# Copies a received course into the current account's private local segments.
class RemoteSegmentImportsController < ApplicationController
  def create
    @segment = RemoteSegment.find(params[:id])
    policy = Federation::RemoteSegmentPolicy.new(
      segment: @segment, principal: Workouts::PublicationPrincipal.browser(current_user)
    )
    raise ActiveRecord::RecordNotFound unless policy.allowed?(resource: :segment)

    result = Segments::RemoteImporter.new(user: current_user, remote_segment: @segment).call!
    redirect_to segment_path(result.segment), notice: notice_for(result)
  rescue Segments::RemoteImporter::ImportError => error
    redirect_to remote_segment_path(@segment), alert: error.message
  end

  private

  def notice_for(result)
    [ I18n.t("segments.remote_copy.success"), *result.warnings ].join(" ")
  end
end
