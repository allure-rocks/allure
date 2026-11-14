# frozen_string_literal: true

module Federation
  # Application-mediated serving of the course media. The browser and remote
  # peers never see a raw Active Storage URL. The route image exists in a light
  # and a dark variant; each has its own signed path (DESIGN.md §15.4).
  class SegmentMediaController < ProtocolController
    def gpx
      send_publication_media(
        resource: :gpx,
        attachment: ->(publication) { publication.sanitized_attachment(:gpx) },
        filename: "segment-#{params[:id]}.gpx",
        content_type: "application/gpx+xml",
        disposition: "attachment"
      )
    end

    def route_image
      send_publication_media(
        resource: :route_image,
        attachment: ->(publication) { publication.route_image_variant(:light) },
        filename: "segment-#{params[:id]}.png",
        content_type: "image/png",
        disposition: "inline"
      )
    end

    def route_image_dark
      send_publication_media(
        resource: :route_image,
        attachment: ->(publication) { publication.route_image_variant(:dark) },
        filename: "segment-#{params[:id]}-dark.png",
        content_type: "image/png",
        disposition: "inline"
      )
    end

    private

    def send_publication_media(resource:, attachment:, filename:, content_type:, disposition:)
      publication = SegmentPublication.find_by_short_id!(params[:id])
      actor = publication.audience == "followers" ? verified_remote_actor : nil
      policy = Segments::PublicationPolicy.new(
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
