# frozen_string_literal: true

module Federation
  class NodeInfoController < ProtocolController
    SUPPORTED_VERSIONS = %w[2.1 2.2].freeze

    def discovery
      render_protocol_json(
        {
          "links" => SUPPORTED_VERSIONS.map do |version|
            {
              "rel" => "http://nodeinfo.diaspora.software/ns/schema/#{version}",
              "href" => federation_config.nodeinfo_uri(version)
            }
          end
        },
        status: :ok,
        content_type: Allure::Federation::MediaTypes::NODE_INFO
      )
    end

    def show
      version = params[:version].to_s
      return render_not_found(content_type: Allure::Federation::MediaTypes::NODE_INFO) unless SUPPORTED_VERSIONS.include?(version)

      render_protocol_json(
        Federation::Serializers::NodeInfo.new(version: version).call,
        status: :ok,
        content_type: Allure::Federation::MediaTypes::NODE_INFO
      )
    end
  end
end
