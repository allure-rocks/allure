# frozen_string_literal: true

module Federation
  class ProcessInboxItemJob < ApplicationJob
    queue_as :federation

    discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound

    def perform(item)
      return unless Allure::Federation::Config.enabled?
      return if item.terminal?
      return unless item.claim!

      processor = nil
      FederationInboxItem.transaction do
        processor = Federation::Inbox::Processor.new(item:)
        processor.call!
        item.mark_processed! if item.reload.status == "processing"
      end
      processor.outbox_events.each do |event|
        Federation::ExpandOutboxEventJob.perform_later(event) if event.pending?
      end
      processor.media_attachments.each do |attachment|
        attachment.fetch_job_class.perform_later(
          attachment.id, attachment.source_domain
        )
      end
    rescue StandardError => error
      retry_item(item, error)
    end

    private

    def retry_item(item, error)
      item.reload
      return unless item.status == "processing"

      if item.retry!(error:)
        self.class.set(wait_until: item.next_attempt_at).perform_later(item)
      end
    end
  end
end
