# frozen_string_literal: true

module Api
  module Rest
    module V1
      # The OpenAPI document (PLAN_API.md §12). Members-only like every page,
      # it is the one API resource that also accepts a signed-in browser, so
      # the reference page can load it; any valid token, whatever its scopes,
      # reads it too.
      class DocumentsController < ApplicationController
        allow_unauthenticated_access

        def show
          return render_unauthorized unless authenticated? || token_holder?

          response.headers["Cache-Control"] = "private, max-age=0, must-revalidate"
          return unless stale?(etag: Document.etag)

          document = Document.served
          if params[:format] == "yaml"
            render plain: document.to_yaml, content_type: "application/yaml"
          else
            render json: document
          end
        end

        private

        def token_holder?
          secret = request.authorization.to_s[/\ABearer[ ]+(\S+)\s*\z/i, 1]
          token = ApiToken.authenticate(secret)
          token.present? && !token.user.suspended?
        end

        def render_unauthorized
          response.headers["WWW-Authenticate"] = %(Bearer realm="Allure")
          render json: {
            type: "#{Allure::Federation.config.base_url}/developers/api#problem-missing_token",
            title: Problems.title("missing_token"), status: 401, code: "missing_token",
            detail: Problems.detail("missing_token")
          }, status: :unauthorized, content_type: "application/problem+json"
        end
      end
    end
  end
end
