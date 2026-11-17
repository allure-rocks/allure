# frozen_string_literal: true

module Webhooks
  # One attempt of one delivery (docs/dev/API.md). A 2xx succeeds, a 410
  # disables the endpoint (`gone`), anything else schedules the next retry
  # until they run out. A suspended account's or a paused endpoint's delivery
  # waits, pending, for the recovery sweep.
  class DeliverJob < ApplicationJob
    queue_as :webhooks

    limits_concurrency to: 2, key: ->(delivery) { "webhook-endpoint-#{delivery.webhook_endpoint_id}" }, duration: 1.minute

    # An attempt holds the delivery this long, so a second job for it (the
    # recovery sweep's, or a retry's) finds it taken and stops.
    LEASE = 2.minutes

    def perform(delivery, transport: Transport.new, now: Time.current)
      endpoint = delivery.webhook_endpoint
      return unless endpoint.deliverable? && !endpoint.user.deactivated?
      return unless claim(delivery, now)

      outcome = transport.deliver(endpoint, delivery.webhook_event, now:)
      settle(delivery, endpoint, outcome, now)
    end

    private

    def claim(delivery, now)
      claimed = false
      delivery.with_lock do
        due = delivery.pending? && (delivery.next_attempt_at.nil? || delivery.next_attempt_at <= now)
        if due
          delivery.update_columns(next_attempt_at: now + LEASE)
          claimed = true
        end
      end
      claimed
    end

    def settle(delivery, endpoint, outcome, now)
      attempts = delivery.attempts + 1
      common = { attempts:, last_attempt_at: now, last_status_code: outcome.status_code }
      if outcome.success?
        delivery.update!(**common, status: "succeeded", succeeded_at: now, last_error: nil, next_attempt_at: nil)
        endpoint.record_success!
      elsif outcome.gone?
        delivery.update!(**common, status: "failed", last_error: "gone", next_attempt_at: nil)
        endpoint.disable!("gone", at: now)
        abandon_pending(endpoint, now)
      else
        retry_or_abandon(delivery, common, outcome, attempts, now)
        abandon_pending(endpoint, now) if endpoint.record_failure!(at: now)
      end
    end

    def retry_or_abandon(delivery, common, outcome, attempts, now)
      wait = WebhookDelivery::RETRY_DELAYS[attempts - 1]
      if wait
        delivery.update!(**common, last_error: outcome.error, next_attempt_at: now + wait)
        self.class.set(wait_until: now + wait).perform_later(delivery)
      else
        delivery.update!(**common, status: "abandoned", last_error: outcome.error, next_attempt_at: nil)
      end
    end

    # A disabled endpoint receives nothing more; what was waiting is given up.
    def abandon_pending(endpoint, now)
      endpoint.deliveries.pending.update_all(status: "abandoned", last_error: "endpoint_disabled", next_attempt_at: nil,
                                             updated_at: now)
    end
  end
end
