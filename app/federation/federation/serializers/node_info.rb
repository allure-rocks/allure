# frozen_string_literal: true

module Federation
  module Serializers
    class NodeInfo
      def initialize(version:)
        @version = version
      end

      def call
        {
          "version" => @version,
          "software" => {
            "name" => "allure",
            "version" => ENV.fetch("ALLURE_VERSION", Allure::VERSION)
          },
          "protocols" => [ "activitypub" ],
          "services" => {
            "inbound" => [],
            "outbound" => []
          },
          "openRegistrations" => false,
          "usage" => {
            "users" => { "total" => User.count },
            "localPosts" => WorkoutPublication.where(status: "active").count,
            "localComments" => 0
          },
          "metadata" => metadata
        }
      end

      private

      # NodeInfo leaves `metadata` free-form. Only configured presentation
      # values are exposed; no permanent identity is repeated here.
      def metadata
        values = { "nodeName" => Allure::Instance.name }
        values["nodeDescription"] = Allure::Instance.description if Allure::Instance.description
        if Allure::Instance.hosted_by?
          host = { "name" => Allure::Instance.host_name }
          host["url"] = Allure::Instance.host_url if Allure::Instance.host_url
          values["host"] = host
        end
        values
      end
    end
  end
end
