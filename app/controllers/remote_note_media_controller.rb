# frozen_string_literal: true

# Serves cached remote media through this instance only. The browser never
# talks to the origin server, and anonymous visitors never see remote copies.
# The route image is served in the viewer's requested variant, falling back to
# the other cached one (DESIGN.md §15.4).
class RemoteNoteMediaController < ApplicationController
  def gpx
    serve("gpx")
  end

  def route_image
    serve("route_image")
  end

  private

  def serve(kind)
    note = RemoteNote.find(params[:id])
    policy = Federation::RemoteNotePolicy.new(
      note:, principal: Workouts::PublicationPrincipal.browser(current_user)
    )
    return head :not_found unless policy.allowed?(resource: :media)

    attachment = if kind == "route_image"
      Federation::RemoteNoteView.new(note).route_image_attachment(params[:theme])
    else
      note.attachments.cached.find_by(kind:)
    end
    return head :not_found unless attachment&.blob

    response.headers["Cache-Control"] = "private, no-store"
    send_data attachment.blob.download,
              filename: filename_for(attachment),
              type: attachment.blob.content_type,
              disposition: "inline"
  rescue ActiveRecord::RecordNotFound, ActiveStorage::FileNotFoundError, ArgumentError
    head :not_found
  end

  def filename_for(attachment)
    return "route.gpx" if attachment.kind == "gpx"

    attachment.theme == "dark" ? "route-dark.png" : "route.png"
  end
end
