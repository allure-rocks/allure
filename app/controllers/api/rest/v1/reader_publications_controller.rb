# frozen_string_literal: true

module Api
  module Rest
    module V1
      # A local publication as a reader reads it (PLAN_API.md §6.5, §7.2): only
      # while `Workouts::PublicationPolicy` serves it to the token's account,
      # and only the resources the policy allows. The owner reads their own
      # publications the same way, from the snapshot.
      class ReaderPublicationsController < BaseController
        include SocialReading

        require_scope "social:read"

        def show
          publication = readable_publication
          context = reading_context([ publication.workout ])
          render json: SocialSerializers.publication(publication, viewer: viewer_actor, principal:, context:)
        end

        # The sanitized track the snapshot froze, never the recorded one.
        def track
          publication = readable_publication(:track)
          render json: publication.track, content_type: "application/geo+json"
        end

        def route_image
          theme = theme_param
          publication = readable_publication(:route_image)
          send_image(publication.route_image_variant(theme))
        end

        # The thread of this publication's audience, as the web shows it.
        def comments
          publication = readable_publication
          audiences = Workouts::ReadableAudiences.for(user: current_user, workout: publication.workout) & [ publication.audience ]
          listing = Comments::Listing.new(target: publication.workout, viewer: viewer_actor, audiences:).call
          render json: { data: listing.entries.map { SocialSerializers.comment_entry(it) } }
        end

        private

        def readable_publication(resource = :workout)
          publication = WorkoutPublication.active.includes(:workout, actor: :user).find_by_short_id!(params[:id])
          policy = Workouts::PublicationPolicy.new(publication:, principal:)
          raise ActiveRecord::RecordNotFound unless publication.workout && policy.allowed?(resource:)

          publication
        end
      end
    end
  end
end
