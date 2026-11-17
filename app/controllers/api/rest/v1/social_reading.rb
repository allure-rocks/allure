# frozen_string_literal: true

module Api
  module Rest
    module V1
      # The reader the social endpoints act as (docs/dev/API.md): the token's
      # account as a signed-in browser, the principal every web page uses, and
      # the page's batched reaction and comment counts.
      module SocialReading
        extend ActiveSupport::Concern

        included do
          rescue_from Federation::ActorProvisioner::IdentityConflict do
            render_problem(:not_found, "not_found")
          end
        end

        private

        def viewer_actor = @viewer_actor ||= Federation::ActorProvisioner.new(user: current_user).call!

        def principal = Workouts::PublicationPrincipal.browser(current_user)

        def reading_context(targets)
          {
            reactions: Reactions::Summaries.new(targets:, viewer: viewer_actor).call,
            comments: Comments::Counts.new(targets:, viewer: current_user).call
          }
        end

        def send_image(attachment)
          raise ActiveRecord::RecordNotFound unless attachment&.blob

          send_data attachment.blob.download, type: attachment.blob.content_type, disposition: "inline",
                                              filename: "route.png"
        rescue ActiveStorage::FileNotFoundError
          raise ActiveRecord::RecordNotFound
        end

        def theme_param
          value = params[:theme].presence || "light"
          raise BaseController::InvalidParameter, "theme" unless %w[light dark].include?(value)

          value
        end
      end
    end
  end
end
