# frozen_string_literal: true

module Federation
  class WorkoutsController < ProtocolController
    def show
      publication = WorkoutPublication.find_by_short_id!(params[:id])
      actor = publication.audience == "followers" ? verified_remote_actor : nil
      policy = Workouts::PublicationPolicy.new(
        publication:,
        principal: Workouts::PublicationPrincipal.protocol(actor)
      )
      return render_not_found unless policy.allowed?

      render_protocol_json(
        Federation::Serializers::WorkoutNote.new(
          publication:, actor: publication.actor
        ).call,
        status: :ok,
        content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB
      )
    rescue ArgumentError, Federation::Serializers::WorkoutNote::Unavailable
      render_not_found
    end
  end
end
