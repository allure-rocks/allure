# frozen_string_literal: true

module Federation
  class WebfingerController < ProtocolController
    def show
      username, domain = resource_parts
      return render_not_found(content_type: Allure::Federation::MediaTypes::WEBFINGER) unless domain == federation_config.domain

      actor = local_actor_for(username)
      return render_not_found(content_type: Allure::Federation::MediaTypes::WEBFINGER) unless actor&.local? && !actor.tombstoned?

      render_protocol_json(
        {
          "subject" => federation_config.acct(actor.user.username),
          "aliases" => [ actor.uri, federation_config.profile_url(actor.user.username) ],
          "links" => [
            {
              "rel" => "self",
              "type" => Allure::Federation::MediaTypes::ACTIVITY_PUB,
              "href" => actor.uri
            }
          ]
        },
        status: :ok,
        content_type: Allure::Federation::MediaTypes::WEBFINGER
      )
    end

    private

    def resource_parts
      resource = params[:resource].to_s
      match = resource.match(/\Aacct:([a-zA-Z0-9_]{1,30})@([^@]+)\z/)
      return [ nil, nil ] unless match

      [ match[1].downcase, match[2] ]
    end
  end
end
