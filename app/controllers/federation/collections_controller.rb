# frozen_string_literal: true

module Federation
  class CollectionsController < ProtocolController
    COLLECTIONS = %w[outbox followers following].freeze

    def show
      collection = params[:collection].to_s
      return render_not_found unless COLLECTIONS.include?(collection)

      actor = local_actor_for(params[:username])
      return render_not_found unless actor
      return render_tombstone(actor) if actor.tombstoned?

      viewer_actor = collection == "outbox" ? verified_remote_actor : nil
      serializer = Federation::Serializers::OrderedCollection.new(
        actor:, collection:, viewer_actor:, page: params[:page]
      )
      payload = params[:page].present? ? serializer.page : serializer.collection

      render_protocol_json(
        payload,
        status: :ok,
        content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB
      )
    end
  end
end
