# frozen_string_literal: true

module Federation
  module RemoteMedia
    # Durable intent drives media recovery: stale fetches are released, and
    # pending or due failed descriptors are re-enqueued without duplicating
    # rows. Runs from Federation::RecoveryJob.
    class Recovery
      STALE_FETCHING_AFTER = 10.minutes
      BATCH_LIMIT = 500
      ATTACHMENT_CLASSES = [ RemoteNoteAttachment, RemoteSegmentAttachment ].freeze

      Result = Data.define(:released, :enqueued)

      def initialize(now: Time.current, limit: BATCH_LIMIT)
        @now = now
        @limit = limit
      end

      def call
        Result.new(released: release_stale_fetching, enqueued: enqueue_due)
      end

      private

      def release_stale_fetching
        count = 0
        ATTACHMENT_CLASSES.each do |model|
          count += release_stale_fetching_for(model)
        end
        count
      end

      def release_stale_fetching_for(model)
        count = 0
        model.where(status: "fetching")
          .where("updated_at < ?", @now - STALE_FETCHING_AFTER)
          .limit(@limit).each do |attachment|
          attachment.update!(status: "failed", next_attempt_at: @now, last_error: "fetch lease expired")
          count += 1
        rescue StandardError => error
          Rails.error.report(error, handled: true, context: { component: self.class.name, attachment_id: attachment.id })
        end
        count
      end

      def enqueue_due
        count = 0
        ATTACHMENT_CLASSES.each do |model|
          count += enqueue_due_for(model)
        end
        count
      end

      def enqueue_due_for(model)
        count = 0
        due = model.where(status: %w[pending failed])
        due
          .where(next_attempt_at: nil)
          .or(due.where(next_attempt_at: ..@now))
          .limit(@limit).each do |attachment|
          next if attachment.attempts >= Fetch::MAX_ATTEMPTS

          attachment.fetch_job_class.perform_later(attachment.id, attachment.source_domain)
          count += 1
        rescue StandardError => error
          Rails.error.report(error, handled: true, context: { component: self.class.name, attachment_id: attachment.id })
        end
        count
      end
    end
  end
end
