# frozen_string_literal: true

module Webhooks
  # Every few minutes (docs/dev/API.md): re-enqueues due deliveries whose job
  # was lost or that waited on a paused endpoint or a suspended account, and
  # prunes events and deliveries older than 30 days.
  class RecoveryJob < ApplicationJob
    queue_as :webhooks

    BATCH = 500

    def perform(now: Time.current)
      WebhookDelivery.due(now).joins(webhook_endpoint: :user)
                     .merge(WebhookEndpoint.deliverable).where(users: { suspended_at: nil, deletion_scheduled_at: nil })
                     .order(:next_attempt_at, :id).limit(BATCH)
                     .each { DeliverJob.perform_later(it) }
      WebhookEvent.prunable(now).in_batches(of: 1_000).delete_all
    end
  end
end
