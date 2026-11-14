# frozen_string_literal: true

module Api
  module Rest
    module V1
      # An unknown path under the namespace answers a problem document, not the
      # HTML error page, whether or not a token was sent.
      class FallbacksController < ActionController::API
        def not_found
          render json: {
            type: "#{Allure::Federation.config.base_url}/developers/api#problem-not_found",
            title: Problems.title("not_found"), status: 404, code: "not_found", detail: Problems.detail("not_found")
          }, status: :not_found, content_type: "application/problem+json"
        end
      end
    end
  end
end
