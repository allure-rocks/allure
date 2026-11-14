# frozen_string_literal: true

module Federation
  module RemoteMedia
    # Operator-triggered retry (PLAN_M5 §12.5). It resets terminal failures and
    # re-enqueues them; cached and purged descriptors are final, and an owner
    # that is no longer active has nothing left to fetch.
    class Retry
      RETRYABLE_STATUSES = %w[failed unavailable].freeze
      ATTACHMENT_CLASSES = [ RemoteNoteAttachment, RemoteSegmentAttachment ].freeze

      def initialize(now: Time.current)
        @now = now
      end

      def call
        count = 0
        ATTACHMENT_CLASSES.each do |model|
          model.where(status: RETRYABLE_STATUSES).find_each do |attachment|
            owner = attachment.owner
            next unless owner.active?

            attachment.update!(status: "pending", attempts: 0, next_attempt_at: @now, last_error: nil)
            attachment.fetch_job_class.perform_later(attachment.id, owner.source_domain)
            count += 1
          end
        end
        count
      end
    end
  end
end
