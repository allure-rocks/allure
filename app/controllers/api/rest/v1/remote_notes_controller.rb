# frozen_string_literal: true

module Api
  module Rest
    module V1
      # A received note (docs/dev/API.md), only while
      # `Federation::RemoteNotePolicy` lets the token's account read it: a
      # public note for any member, a followers note with an active
      # entitlement. Media is this instance's cached copy; nothing is fetched
      # from the origin here.
      class RemoteNotesController < BaseController
        include SocialReading

        require_scope "social:read"

        def show
          note = readable_note
          render json: SocialSerializers.remote_note(note, context: reading_context([ note ]))
        end

        def track
          note = readable_note(:track)
          render json: note.representation["track"], content_type: "application/geo+json"
        end

        def route_image
          theme = theme_param
          note = readable_note(:media)
          send_image(Federation::RemoteNoteView.new(note).route_image_attachment(theme))
        end

        # The thread the origin hosts, as this instance holds it.
        def comments
          note = readable_note
          listing = Comments::Listing.new(target: note, viewer: viewer_actor).call
          render json: { data: listing.entries.map { SocialSerializers.comment_entry(it) } }
        end

        private

        def readable_note(resource = :note)
          note = RemoteNote.includes(:actor, :attachments).find_by!(uuid: Allure::ShortId.decode(params[:id].to_s))
          policy = Federation::RemoteNotePolicy.new(note:, principal:)
          raise ActiveRecord::RecordNotFound unless policy.allowed?(resource:)

          note
        rescue ArgumentError
          raise ActiveRecord::RecordNotFound
        end
      end
    end
  end
end
