# frozen_string_literal: true

module Federation
  # Serves the sanitized publication media over the ActivityPub wire. The route
  # image exists in a light and a dark variant; each has its own signed path so
  # the URL itself identifies the variant (DESIGN.md §15.4).
  class MediaController < ProtocolController
    def gpx
      send_publication_media(
        resource: :gpx,
        attachment: ->(publication) { publication.sanitized_attachment(:gpx) },
        filename: "route-#{params[:id]}.gpx",
        content_type: "application/gpx+xml",
        disposition: "attachment"
      )
    end

    def route_image
      send_publication_media(
        resource: :route_image,
        attachment: ->(publication) { publication.route_image_variant(:light) },
        filename: "route-#{params[:id]}.png",
        content_type: "image/png",
        disposition: "inline"
      )
    end

    def route_image_dark
      send_publication_media(
        resource: :route_image,
        attachment: ->(publication) { publication.route_image_variant(:dark) },
        filename: "route-#{params[:id]}-dark.png",
        content_type: "image/png",
        disposition: "inline"
      )
    end

    private

    def send_publication_media(resource:, attachment:, filename:, content_type:, disposition:)
      publication = WorkoutPublication.find_by_short_id!(params[:id])
      actor = publication.audience == "followers" ? verified_remote_actor : nil
      policy = Workouts::PublicationPolicy.new(
        publication:,
        principal: Workouts::PublicationPrincipal.protocol(actor)
      )
      return render_not_found unless policy.allowed?(resource:)

      resolved = attachment.call(publication)
      return render_not_found unless resolved

      response.headers["Cache-Control"] = "private, no-store"
      send_data resolved.download, filename:, type: content_type, disposition:
    rescue ArgumentError
      render_not_found
    end
  end
end
