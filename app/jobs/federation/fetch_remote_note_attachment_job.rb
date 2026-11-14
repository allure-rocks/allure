# frozen_string_literal: true

module Federation
  # Fetches one pending media descriptor. The second argument exists only so
  # the per-domain concurrency key can be computed at enqueue time without a
  # database read.
  class FetchRemoteNoteAttachmentJob < ApplicationJob
    queue_as :federation_media
    limits_concurrency to: 2, key: ->(_attachment_id, source_domain) { source_domain }, duration: 5.minutes

    discard_on ActiveJob::DeserializationError

    def perform(attachment_id, _source_domain = nil)
      return unless Allure::Federation::Config.enabled?

      attachment = RemoteNoteAttachment.find_by(id: attachment_id)
      return unless attachment

      RemoteMedia::Fetch.new(attachment:).call!
    end
  end
end
