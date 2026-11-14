# frozen_string_literal: true

module Api
  module Rest
    module V1
      # The REST API's request boundary (PLAN_API.md §4.5, §5). It reads only
      # `Authorization: Bearer`, never the session cookie, so no API mutation
      # is reachable by a cross-site request; it answers RFC 9457 problems in
      # English; and every query is scoped through the token's account.
      class BaseController < ActionController::API
        class InvalidParameter < StandardError
          attr_reader :parameter

          def initialize(parameter, message = nil)
            @parameter = parameter
            super(message || "The #{parameter} parameter is invalid.")
          end
        end

        DEFAULT_LIMIT = 25
        MAX_LIMIT = 100
        MUTATIONS = %w[POST PATCH PUT DELETE].freeze

        rescue_from ActiveRecord::RecordNotFound do
          render_problem(:not_found, "not_found")
        end
        rescue_from ActionController::ParameterMissing do |error|
          render_problem(:bad_request, "invalid_parameter", detail: "The #{error.param} parameter is required.")
        end
        rescue_from InvalidParameter do |error|
          render_problem(:bad_request, "invalid_parameter", detail: error.message)
        end
        rescue_from Cursor::Invalid do
          render_problem(:bad_request, "invalid_cursor")
        end
        rescue_from ActionDispatch::Http::Parameters::ParseError do
          render_problem(:bad_request, "invalid_parameter", detail: "The request body is not valid JSON.")
        end

        # Bodies are read as sent: no copy under a `workout` key, so unknown
        # fields can be refused.
        wrap_parameters false

        include Idempotency

        around_action :in_english
        before_action :authenticate_token!
        before_action :private_caching

        # One bucket per token across every controller behind this boundary
        # (PLAN_API.md §4.6): without `scope:` Rails keys the count by
        # controller path, and a token would get the limit once per resource.
        RATE_LIMIT_SCOPE = "api"

        rate_limit to: 300, within: 1.minute, by: -> { Current.api_token.id }, name: "api-requests",
                   scope: RATE_LIMIT_SCOPE, with: -> { render_rate_limited(1.minute) }
        rate_limit to: 60, within: 1.minute, by: -> { Current.api_token.id }, name: "api-mutations",
                   scope: RATE_LIMIT_SCOPE, if: -> { mutation_request? },
                   with: -> { render_rate_limited(1.minute) }

        # Declares the scope an action needs (PLAN_API.md §4.3). Several
        # scopes mean any one of them suffices.
        def self.require_scope(*scopes, **options)
          before_action(**options) { ensure_scope!(scopes) }
        end

        private

        def current_user = Current.user

        def mutation_request? = MUTATIONS.include?(request.request_method)

        def authenticate_token!
          secret = bearer_secret
          token = ApiToken.authenticate(secret)
          return render_unauthorized(secret.nil? ? "missing_token" : "invalid_token") unless token

          if token.user.suspended?
            render_problem(:forbidden, "account_suspended")
          elsif token.user.deletion_scheduled?
            render_problem(:forbidden, "account_deletion_scheduled")
          elsif Auth::SecondFactorPolicy.new(token.user).required?
            render_problem(:forbidden, "second_factor_required")
          else
            Current.api_token = token
            token.record_use!
          end
        end

        def bearer_secret
          header = request.authorization.to_s
          match = header.match(/\ABearer[ ]+(\S+)\s*\z/i)
          match && match[1]
        end

        def ensure_scope!(scopes)
          # The `scope` label of allure_api_requests_total (PLAN_API.md §14).
          request.env["allure.api_scope"] = scopes.first.to_s
          return if scopes.any? { Current.api_token.scope?(it) }

          render_problem(:forbidden, "insufficient_scope",
                         detail: "This operation needs the #{scopes.join(' or ')} scope.")
        end

        def render_unauthorized(code)
          response.headers["WWW-Authenticate"] = %(Bearer realm="Allure", error="#{code == 'missing_token' ? 'invalid_request' : 'invalid_token'}")
          render_problem(:unauthorized, code)
        end

        def render_rate_limited(window)
          response.headers["Retry-After"] = window.to_i.to_s
          render_problem(:too_many_requests, "rate_limited")
        end

        # `extensions` are extra members of the problem (RFC 9457 §3.2), such
        # as a publication refusal's `reason`.
        def render_problem(status, code, detail: nil, errors: nil, **extensions)
          status_code = Rack::Utils.status_code(status)
          body = {
            type: "#{Allure::Federation.config.base_url}/developers/api#problem-#{code}",
            title: Problems.title(code),
            status: status_code,
            code:,
            detail: detail || Problems.detail(code),
            errors:,
            **extensions
          }.compact
          render json: body, status: status_code, content_type: "application/problem+json"
        end

        # 422 with one `{ field, code, detail }` per refused field
        # (PLAN_API.md §5).
        def render_validation(errors)
          render_problem(:unprocessable_content, "validation_failed", errors:)
        end

        # A model's validation errors as problem field errors, in English.
        def field_errors(record, rename: {})
          record.errors.map do |error|
            { field: rename.fetch(error.attribute, error.attribute).to_s, code: error.type.to_s,
              detail: error.full_message }
          end
        end

        def in_english(&) = I18n.with_locale(:en, &)

        def private_caching
          response.headers["Cache-Control"] = "private, max-age=0, must-revalidate"
        end

        def page_limit
          return DEFAULT_LIMIT if params[:limit].blank?

          value = Integer(params[:limit].to_s, 10)
          raise InvalidParameter, "limit" unless value.between?(1, MAX_LIMIT)

          value
        rescue ArgumentError
          raise InvalidParameter, "limit"
        end

        # Keyset pagination over `column` then the primary key, both in
        # `direction` (PLAN_API.md §5). The cursor is encrypted and bound to
        # `context`, so a cursor from another ordering is refused.
        def paginate(scope, column:, direction:, context:, &serialize)
          limit = page_limit
          table = scope.klass.arel_table
          if params[:cursor].present?
            value, id = Cursor.decode(params[:cursor], context:)
            beyond = direction == :asc ? :gt : :lt
            scope = scope.where(table[column].public_send(beyond, value)
                                  .or(table[column].eq(value).and(table[:id].public_send(beyond, id))))
          end
          records = scope.reorder(column => direction, id: direction).limit(limit + 1).to_a
          more = records.size > limit
          records = records.first(limit)
          last = records.last
          {
            data: records.map(&serialize),
            next_cursor: (Cursor.encode([ Cursor.dump(last.public_send(column)), last.id ], context:) if more)
          }
        end

        def base_url = Allure::Federation.config.base_url
        def api_url(path) = "#{base_url}#{path}"
      end
    end
  end
end
