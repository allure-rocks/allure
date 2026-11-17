# frozen_string_literal: true

# Serves an active publication's sanitized media to a signed-in local browser
# session. The remote-facing wire endpoints stay on Federation::MediaController
# and authenticate HTTP signatures; local viewers authorize through
# Workouts::PublicationPolicy with a browser principal instead, so the owner
# and another signed-in account never share the remote signed-actor
# assumptions (docs/dev/PUBLISHING.md). Viewing requires an account
# (docs/dev/ACCESS.md), so no anonymous principal reaches the policy here.
#
# The route image is served in the viewer's requested variant, falling back to
# the other one (DESIGN.md §15.4).
class PublicationMediaController < ApplicationController
  def gpx
    serve(
      publication.sanitized_attachment(:gpx),
      resource: :gpx,
      filename: "route-#{publication.to_param}.gpx",
      content_type: "application/gpx+xml",
      disposition: "attachment"
    )
  end

  def route_image
    serve(
      publication.route_image_variant(params[:theme]),
      resource: :route_image,
      filename: "route-#{publication.to_param}.png",
      content_type: "image/png",
      disposition: "inline"
    )
  end

  # A frozen photo copy (docs/dev/PHOTOS.md), `display` or `thumbnail`.
  def photo
    photo = publication.photos.find_by_short_id!(params[:photo_id])
    variant = params[:variant] == "thumbnail" ? :thumbnail : :display
    serve(
      (photo.public_send(variant) if photo.public_send(variant).attached?),
      resource: :photos,
      filename: "photo-#{photo.to_param}.webp",
      content_type: "image/webp",
      disposition: "inline"
    )
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def serve(attachment, resource:, filename:, content_type:, disposition:)
    policy = Workouts::PublicationPolicy.new(
      publication:,
      principal: Workouts::PublicationPrincipal.browser(current_user)
    )
    return head :not_found unless policy.allowed?(resource:)

    return head :not_found unless attachment

    response.headers["Cache-Control"] = "private, no-store"
    send_data attachment.download, filename:, type: content_type, disposition:
  rescue ArgumentError, ActiveStorage::FileNotFoundError
    head :not_found
  end

  def publication
    @publication ||= WorkoutPublication.find_by_short_id!(params[:id])
  end
end
