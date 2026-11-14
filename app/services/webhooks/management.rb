# frozen_string_literal: true

module Webhooks
  # What the settings pages and the REST API both do to an endpoint
  # (PLAN_API.md §6.6), so the two never diverge.
  module Management
    class Inactive < StandardError; end

    module_function

    # Saves the endpoint; true on success. `active: true` also re-enables an
    # endpoint the system disabled.
    def save(endpoint, url: nil, description: nil, events: nil, active: nil, fields: [])
      endpoint.url = url.to_s.strip if fields.include?(:url)
      endpoint.description = description if fields.include?(:description)
      endpoint.events = normalize_events(events) if fields.include?(:events)
      if fields.include?(:active)
        endpoint.active = active
        if active && endpoint.disabled?
          endpoint.disabled_at = nil
          endpoint.disabled_reason = nil
          endpoint.consecutive_failures = 0
          endpoint.first_failure_at = nil
        end
      end
      saved = endpoint.save
      endpoint.withdraw_disabled_notice if saved && fields.include?(:active) && active
      saved
    end

    def normalize_events(events)
      list = Array(events).map(&:to_s).compact_blank.uniq
      list.include?(WebhookEndpoint::ALL_EVENTS) ? [ WebhookEndpoint::ALL_EVENTS ] : list
    end

    def ping!(endpoint)
      raise Inactive unless endpoint.deliverable?

      Events.ping(endpoint)
    end

    # A new delivery of the same event to the same endpoint; the receiver
    # sees the same `webhook-id`.
    def redeliver!(delivery)
      endpoint = delivery.webhook_endpoint
      raise Inactive unless endpoint.deliverable?

      copy = delivery.webhook_event.deliveries.create!(webhook_endpoint: endpoint, redelivery_of: delivery,
                                                       next_attempt_at: Time.current)
      DeliverJob.perform_later(copy)
      copy
    end

    # Deleting an endpoint gives up what was waiting for it.
    def destroy!(endpoint)
      endpoint.withdraw_disabled_notice
      endpoint.destroy!
    end
  end
end
