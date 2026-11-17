# frozen_string_literal: true

module Api
  module Rest
    module V1
      # Webhook endpoints and their deliveries (docs/dev/API.md). The
      # secret appears only in the responses that create or rotate it.
      module WebhookSerializers
        module_function

        def endpoint(endpoint, last_delivery: :load, secret: nil)
          last_delivery = endpoint.deliveries.newest_first.first if last_delivery == :load
          body = {
            id: endpoint.to_param,
            url: endpoint.url,
            description: endpoint.description,
            events: endpoint.events,
            active: endpoint.active,
            state: endpoint.state,
            disabled_at: Formats.time(endpoint.disabled_at),
            consecutive_failures: endpoint.consecutive_failures,
            last_delivery: (last_delivery && { id: last_delivery.to_param, status: last_delivery.status,
                                               status_code: last_delivery.last_status_code,
                                               at: Formats.time(last_delivery.last_attempt_at || last_delivery.created_at) }),
            created_at: Formats.time(endpoint.created_at),
            updated_at: Formats.time(endpoint.updated_at)
          }
          body[:secret] = secret if secret
          body
        end

        def delivery(delivery)
          event = delivery.webhook_event
          {
            id: delivery.to_param,
            event: { id: event.public_id, type: event.event_type, created_at: Formats.time(event.occurred_at) },
            status: delivery.status,
            attempts: delivery.attempts,
            last_status_code: delivery.last_status_code,
            last_error: delivery.last_error,
            last_attempt_at: Formats.time(delivery.last_attempt_at),
            next_attempt_at: (Formats.time(delivery.next_attempt_at) if delivery.pending?),
            succeeded_at: Formats.time(delivery.succeeded_at),
            redelivery_of_id: delivery.redelivery_of&.to_param,
            created_at: Formats.time(delivery.created_at)
          }
        end
      end
    end
  end
end
