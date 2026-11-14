# frozen_string_literal: true

module Api
  module Rest
    module V1
      # Webhook management (PLAN_API.md §6.6), the same operations as the
      # settings page, through `Webhooks::Management`.
      class WebhooksController < BaseController
        EDITABLE = %w[url description events active].freeze
        DELIVERY_WINDOW = 30.days

        rescue_from Webhooks::Management::Inactive do
          render_problem(:conflict, "webhook_inactive")
        end

        require_scope "webhooks"
        idempotent only: %i[create ping rotate_secret redeliver]

        def index
          endpoints = current_user.webhook_endpoints.newest_first
          render json: { data: endpoints.map { WebhookSerializers.endpoint(it) } }
        end

        def show
          render json: WebhookSerializers.endpoint(owned_endpoint)
        end

        def create
          endpoint = current_user.webhook_endpoints.new
          errors = unknown_fields
          return render_validation(errors) if errors.any?
          return render_validation(field_errors(endpoint)) unless save(endpoint, %i[url description events active])

          response.headers["Location"] = api_url("/api/rest/v1/webhooks/#{endpoint.to_param}")
          render json: WebhookSerializers.endpoint(endpoint, last_delivery: nil, secret: endpoint.secret), status: :created
        end

        def update
          endpoint = owned_endpoint
          errors = unknown_fields
          return render_validation(errors) if errors.any?

          fields = EDITABLE.select { request.request_parameters.key?(it) }.map(&:to_sym)
          return render_validation(field_errors(endpoint)) unless save(endpoint, fields)

          render json: WebhookSerializers.endpoint(endpoint)
        end

        def destroy
          Webhooks::Management.destroy!(owned_endpoint)
          head :no_content
        end

        def ping
          event = Webhooks::Management.ping!(owned_endpoint)
          render json: { event_id: event&.public_id }, status: :accepted
        end

        def rotate_secret
          endpoint = owned_endpoint
          secret = endpoint.rotate_secret!
          render json: WebhookSerializers.endpoint(endpoint, secret:)
        end

        def deliveries
          endpoint = owned_endpoint
          scope = endpoint.deliveries.where(created_at: DELIVERY_WINDOW.ago..)
                          .includes(:webhook_event, :redelivery_of)
          render json: paginate(scope, column: :created_at, direction: :desc, context: "webhook-deliveries") {
            WebhookSerializers.delivery(it)
          }
        end

        def redeliver
          delivery = WebhookDelivery.joins(:webhook_endpoint).where(webhook_endpoints: { user_id: current_user.id })
                                    .find_by_short_id!(params[:id])
          copy = Webhooks::Management.redeliver!(delivery)
          render json: WebhookSerializers.delivery(copy), status: :accepted
        end

        private

        def owned_endpoint = current_user.webhook_endpoints.find_by_short_id!(params[:id])

        def unknown_fields
          (request.request_parameters.keys - EDITABLE).map { { field: it, code: "unknown", detail: "#{it} is not a webhook field." } }
        end

        def save(endpoint, fields)
          body = request.request_parameters
          if fields.include?(:active) && body.key?("active") && ![ true, false ].include?(body["active"])
            endpoint.errors.add(:active, :invalid)
            return false
          end
          fields -= [ :active ] unless body.key?("active")
          Webhooks::Management.save(endpoint, url: body["url"], description: body["description"],
                                              events: body["events"], active: body["active"], fields:)
        end
      end
    end
  end
end
