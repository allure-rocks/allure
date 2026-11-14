# frozen_string_literal: true

module Federation
  class ExpandOutboxEventJob < ApplicationJob
    queue_as :federation

    discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound

    def perform(event)
      return unless Allure::Federation::Config.enabled?
      return if event.terminal?

      Federation::Outbox::Expander.new(event:).call!
    end
  end
end
