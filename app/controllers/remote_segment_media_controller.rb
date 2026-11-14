# frozen_string_literal: true

# Application-mediated serving of cached remote-course media. The browser
# never sees a raw Active Storage URL. The route image is served in the
# viewer's requested variant, falling back to the other cached one
# (DESIGN.md §15.4).
class RemoteSegmentMediaController < ApplicationController
  def gpx
    serve("gpx")
  end

  def route_image
    serve("route_image")
  end

  private

  def serve(kind)
    segment = RemoteSegment.find(params[:id])
    policy = Federation::RemoteSegmentPolicy.new(
      segment:, principal: Workouts::PublicationPrincipal.browser(current_user)
    )
    return head :not_found unless policy.allowed?(resource: :media)

    attachment = if kind == "route_image"
      Federation::RemoteSegmentView.new(segment).route_image_attachment(params[:theme])
    else
      segment.attachments.cached.find_by(kind:)
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
    return "course.gpx" if attachment.kind == "gpx"

    attachment.theme == "dark" ? "course-dark.png" : "course.png"
  end
end
