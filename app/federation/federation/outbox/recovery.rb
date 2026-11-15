# frozen_string_literal: true

module Federation
  module Outbox
    class Recovery
      Result = Data.define(
        :preparing_finalized,
        :events_enqueued,
        :deliveries_enqueued,
        :reconciling_recovered,
        :events_repaired
      )

      STALE_RECONCILING_AFTER = FederationDelivery::LEASE_DURATION * 2
      STALE_PREPARING_AFTER = 15.minutes
      BATCH_LIMIT = 500

      def initialize(now: Time.current, limit: BATCH_LIMIT)
        @now = now
        @limit = limit
      end

      def call
        preparing_finalized = finalize_stale_preparing
        Result.new(
          preparing_finalized:,
          events_enqueued: enqueue_pending_events,
          deliveries_enqueued: enqueue_due_deliveries,
          reconciling_recovered: recover_stale_reconciling,
          events_repaired: repair_expanded_events
        )
      end

      private

      # A Create intent left `preparing` by a lost render job is released after
      # a grace period; delivery proceeds without the image rather than never.
      # The same sweep's pending pass then announces it.
      def finalize_stale_preparing
        count = 0
        FederationOutboxEvent.where(status: "preparing")
          .where("updated_at < ?", @now - STALE_PREPARING_AFTER)
          .limit(@limit).each do |event|
          begin
            event.mark_pending!
            count += 1
          rescue StandardError => error
            Rails.error.report(error, handled: true, context: { component: self.class.name, outbox_event_id: event.id })
          end
        end
        count
      end

      # One enqueue failure must not abort the sweep (docs/dev/PUBLISHING.md): each
      # record is isolated, reported, and retried on the next cadence. Database
      # intent remains authoritative; no logical row is duplicated.
      def enqueue_pending_events
        count = 0
        FederationOutboxEvent.where(status: "pending").order(:created_at, :id).limit(@limit).each do |event|
          begin
            Federation::ExpandOutboxEventJob.perform_later(event)
            count += 1
          rescue StandardError => error
            Rails.error.report(error, handled: true, context: { component: self.class.name, outbox_event_id: event.id })
          end
        end
        count
      end

      def enqueue_due_deliveries
        count = 0
        FederationDelivery.due(@now).limit(@limit).each do |delivery|
          begin
            Federation::DeliverJob.perform_later(delivery)
            count += 1
          rescue StandardError => error
            Rails.error.report(error, handled: true, context: { component: self.class.name, delivery_id: delivery.id })
          end
        end
        count
      end

      def recover_stale_reconciling
        count = 0
        FederationDelivery.where(status: "reconciling")
          .where("updated_at < ?", @now - STALE_RECONCILING_AFTER)
          .limit(@limit).each do |delivery|
          begin
            delivery.with_lock do
              next unless delivery.status == "reconciling"

              if delivery.retry!(error: "stale reconciling delivery recovered", now: @now)
                Federation::DeliverJob.set(wait_until: delivery.next_attempt_at).perform_later(delivery)
                count += 1
              end
            end
          rescue StandardError => error
            Rails.error.report(error, handled: true, context: { component: self.class.name, delivery_id: delivery.id })
          end
        end
        count
      end

      def repair_expanded_events
        count = 0
        FederationOutboxEvent.where(status: "expanded").order(:created_at, :id).limit(@limit).each do |event|
          begin
            event.with_lock do
              count += 1 if event.reconcile_terminal_status!
            end
          rescue StandardError => error
            Rails.error.report(error, handled: true, context: { component: self.class.name, outbox_event_id: event.id })
          end
        end
        count
      end
    end
  end
end
