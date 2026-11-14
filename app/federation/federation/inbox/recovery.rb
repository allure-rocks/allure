# frozen_string_literal: true

module Federation
  module Inbox
    # The inbox counterpart of Outbox::Recovery. Admission enqueues one job
    # per item, so an item whose job was lost stayed pending for good, and one
    # whose worker died mid-processing stayed `processing` (the claim commits
    # before the processing transaction). Due items are enqueued again; a
    # stale `processing` item is retried, and fails at its attempt limit.
    class Recovery
      Result = Data.define(:enqueued, :recovered)

      STALE_PROCESSING_AFTER = 15.minutes
      BATCH_LIMIT = 500

      def initialize(now: Time.current, limit: BATCH_LIMIT)
        @now = now
        @limit = limit
      end

      def call
        Result.new(enqueued: enqueue_due_items, recovered: recover_stale_processing)
      end

      private

      def enqueue_due_items
        count = 0
        FederationInboxItem.due(@now).order(:id).limit(@limit).each do |item|
          Federation::ProcessInboxItemJob.perform_later(item)
          count += 1
        rescue StandardError => error
          Rails.error.report(error, handled: true, context: { component: self.class.name, inbox_item_id: item.id })
        end
        count
      end

      def recover_stale_processing
        count = 0
        FederationInboxItem.where(status: "processing")
          .where(updated_at: ..(@now - STALE_PROCESSING_AFTER))
          .order(:id).limit(@limit).each do |item|
          item.with_lock do
            next unless item.processing? && item.updated_at < @now - STALE_PROCESSING_AFTER

            if item.retry!(error: "stale processing item recovered", now: @now)
              Federation::ProcessInboxItemJob.set(wait_until: item.next_attempt_at).perform_later(item)
            end
            count += 1
          end
        rescue StandardError => error
          Rails.error.report(error, handled: true, context: { component: self.class.name, inbox_item_id: item.id })
        end
        count
      end
    end
  end
end
