# frozen_string_literal: true

module Api
  module Rest
    module V1
      # Publishing through the API (PLAN_API.md §6.4, §9). A second caller of
      # the web's services, with no publication rule of its own except the
      # explicit `acknowledge`: privacy-zone preparation, fail-closed
      # refusals, the safety delay and the replacement of an audience's live
      # publication are `Workouts::Publisher` and its siblings, unchanged.
      class PublicationsController < BaseController
        DELAYS = [ "profile", *PublishingProfile::PUBLISH_DELAYS.keys ].freeze

        rescue_from Workouts::Publisher::PublicationError do |error|
          render_refusal(error.code, error.message)
        end

        require_scope "read", only: :index
        require_scope "publish", except: :index
        idempotent only: %i[create preview activate]

        def index
          workout = owned_workout
          publications = (workout.active_publications.to_a + workout.scheduled_publications.to_a)
          render json: { data: publications.map { PublicationSerializers.publication(it) } }
        end

        def preview
          workout = owned_workout
          return render_credited_workout if workout.credit?

          profile = profile_param
          return if performed?

          readiness = Workouts::PublicationReadiness.new(user: current_user, workout:, profile:).call
          render json: PublicationSerializers.preview(profile, readiness)
        end

        # Publishes with the profile; a live publication of the same audience
        # is replaced by the new one, as the web's Republish.
        def create
          workout = owned_workout
          return render_credited_workout if workout.credit?

          profile = profile_param
          return if performed?

          delay = delay_param
          return if performed?
          return render_acknowledgement_required unless params[:acknowledge] == true

          replaced = workout.active_publication_for(profile.audience)
          publication = if replaced
            Workouts::PublicationReplacement.new(user: current_user, workout:, profile:, delay:, publication: replaced)
                                            .call!.new_publication
          else
            Workouts::Publisher.new(user: current_user, workout:, profile:, delay:).call!
          end

          response.headers["Location"] = api_url("/api/rest/v1/publications/#{publication.to_param}")
          render json: PublicationSerializers.publication(publication.reload), status: :created
        end

        # Leaves the safety delay early.
        def activate
          publication = owned_publication
          return render_problem(:conflict, "not_scheduled") unless publication.scheduled?

          Workouts::ScheduledPublicationActivation.new(publication:, force: true, notify: false).call!
          render json: PublicationSerializers.publication(publication.reload)
        end

        # Moves a scheduled publication's moment to another delay from now.
        def update
          publication = owned_publication
          return render_problem(:conflict, "not_scheduled") unless publication.scheduled?

          unknown = request.request_parameters.keys - %w[delay]
          if unknown.any? || !params.key?(:delay)
            errors = unknown.map { { field: it, code: "unknown", detail: "#{it} cannot be changed." } }
            errors << { field: "delay", code: "required", detail: "Send the new delay." } unless params.key?(:delay)
            return render_validation(errors)
          end
          delay = delay_param(allow_profile: false)
          return if performed?

          Workouts::ScheduledPublicationReschedule.new(user: current_user, workout: publication.workout, delay:, publication:).call!
          render json: PublicationSerializers.publication(publication.reload)
        end

        # Deletes a live publication (the instances it reached are told), or
        # cancels a scheduled one, which nobody has seen.
        def destroy
          publication = owned_publication
          if publication.scheduled?
            Workouts::ScheduledPublicationCancellation.new(user: current_user, publication:).call!
          else
            Workouts::PublicationDeletion.new(user: current_user, workout: publication.workout, publication:).call!
          end
          head :no_content
        end

        private

        def owned_workout
          current_user.workouts.find_by_short_id!(params[:workout_id])
        end

        def owned_publication
          WorkoutPublication.where(status: %w[active scheduled], workout: current_user.workouts)
                            .includes(:workout, :publishing_profile)
                            .find_by_short_id!(params[:id])
        end

        def profile_param
          id = params[:publishing_profile_id]
          profile = current_user.publishing_profiles.find_by(uuid: Allure::ShortId.decode(id.to_s)) if id.is_a?(String)
          if profile.nil?
            render_validation([ { field: "publishing_profile_id", code: id.nil? ? "required" : "unknown_profile",
                                  detail: "Name one of your publishing profiles (GET /publishing_profiles)." } ])
          elsif !profile.publishable?
            render_refusal("followers_unavailable",
                           I18n.t("workouts.publish.errors.followers_unavailable"))
          end
          profile
        rescue ArgumentError
          render_validation([ { field: "publishing_profile_id", code: "unknown_profile",
                                detail: "Name one of your publishing profiles (GET /publishing_profiles)." } ])
          nil
        end

        # Seconds for the services, nil for the profile's own delay.
        def delay_param(allow_profile: true)
          value = params.fetch(:delay, "profile")
          choices = allow_profile ? DELAYS : DELAYS - [ "profile" ]
          unless value.is_a?(String) && choices.include?(value)
            render_validation([ { field: "delay", code: "invalid", detail: "delay must be one of: #{choices.join(', ')}." } ])
            return
          end
          value == "profile" ? nil : PublishingProfile::PUBLISH_DELAYS.fetch(value)
        end

        def render_acknowledgement_required
          render_problem(:unprocessable_content, "acknowledgement_required",
                         detail: "Show your user what will be shared, then send acknowledge: true. " \
                                 "#{PublicationSerializers.copy[:never]} #{PublicationSerializers.copy[:irrevocable]}")
        end

        def render_refusal(reason, message)
          render_problem(:unprocessable_content, "publication_refused", detail: message, reason:)
        end

        # A credit row is never published (PLAN_TOGETHER.md §6.6).
        def render_credited_workout
          render_problem(:unprocessable_content, "credited_workout")
        end
      end
    end
  end
end
