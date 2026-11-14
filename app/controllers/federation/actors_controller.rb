# frozen_string_literal: true

module Federation
  class ActorsController < ProtocolController
    def show
      actor = local_actor_for(params[:username])
      return render_not_found unless actor
      return render_tombstone(actor) if actor.tombstoned?

      unless activity_pub_request?
        return redirect_to "/@#{actor.user.username}", status: :see_other
      end

      render_protocol_json(
        Federation::Serializers::Person.new(actor: actor).call,
        status: :ok,
        content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB
      )
    end
  end
end
