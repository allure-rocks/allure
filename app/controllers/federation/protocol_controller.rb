# frozen_string_literal: true

module Federation
  class ProtocolController < ActionController::API
    before_action :require_federation

    private

    def require_federation
      head :not_found unless Allure::Federation::Config.enabled?
    end

    def federation_config = Allure::Federation.config

    def local_actor_for(raw_username)
      username = raw_username.to_s.downcase
      return unless username.match?(User::USERNAME_FORMAT)

      actor_uri = federation_config.actor_uri(username)
      actor = Actor.find_by(uri: actor_uri)
      return actor if actor&.local?
      return if actor

      user = User.find_by(username: username)
      return unless user

      Federation::ActorProvisioner.new(user: user).call!
    rescue Federation::ActorProvisioner::IdentityConflict
      nil
    end

    def activity_pub_request?
      accepts_any?(Allure::Federation::MediaTypes::ACTIVITY_PUB_ACCEPTED)
    end

    def accepts_any?(media_types)
      request.headers["Accept"].to_s.split(",").any? do |range|
        media_types.include?(range.split(";", 2).first.strip)
      end
    end

    def render_protocol_json(payload, status:, content_type:)
      render json: payload, status:, content_type:
    end

    def render_not_found(content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB)
      render_protocol_json({ "error" => "not_found" }, status: :not_found, content_type:)
    end

    def render_tombstone(actor)
      render_protocol_json(
        Federation::Serializers::Tombstone.new(actor: actor).call,
        status: :gone,
        content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB
      )
    end

    def protocol_headers
      %w[Host Date Digest Signature Content-Type].to_h do |name|
        [ name, request.headers[name] ]
      end.compact
    end

    def verified_remote_actor
      return if request.headers["Signature"].blank?

      Federation::Signature::RequestActor.new(
        method: request.request_method,
        path: request.path,
        headers: protocol_headers,
        body: request.raw_post
      ).call!
    rescue Federation::Signature::RequestActor::InvalidRequest
      nil
    end
  end
end
