# frozen_string_literal: true

module Webhooks
  # Emits one event to an account's webhooks (docs/dev/API.md). Nothing is
  # written for an account with no deliverable endpoint subscribed to the
  # type, nor for a suspended account. Called inside a transaction, it waits
  # for the commit, so an event never announces something rolled back; the
  # payload is built then, from the committed state. `dedupe_key` makes a
  # second emission of the same fact a no-op.
  module Emit
    module_function

    def call(user:, type:, dedupe_key:, now: Time.current, &payload)
      return if user.nil?

      ActiveRecord.after_all_transactions_commit { emit!(user, type, dedupe_key, now, payload) }
    end

    # `only:` sends to that endpoint alone (a ping), whatever it subscribes to.
    def emit!(user, type, dedupe_key, now, payload, only: nil)
      endpoints = if only
        only.deliverable? ? [ only ] : []
      else
        user.webhook_endpoints.deliverable.select { it.subscribed_to?(type) }
      end
      return if endpoints.empty? || user.reload.deactivated?

      event = WebhookEvent.create_or_find_by!(user:, dedupe_key:) do |row|
        row.event_type = type
        row.payload = payload.call
        row.occurred_at = now
      end
      return unless event.previously_new_record?

      endpoints.each do |endpoint|
        delivery = event.deliveries.create!(webhook_endpoint: endpoint, next_attempt_at: now)
        DeliverJob.perform_later(delivery)
      end
      event
    end
  end
end
