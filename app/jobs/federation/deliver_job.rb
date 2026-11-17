# frozen_string_literal: true

module Federation
  class DeliverJob < ApplicationJob
    queue_as :federation

    # At most 5 concurrent deliveries per target authority (docs/dev/FEDERATION.md).
    # The key is computed at enqueue, where the delivery is still a record.
    limits_concurrency to: 5, duration: 5.minutes,
      key: ->(delivery) { Allure::Federation::Authority.domain(delivery.inbox_url) }

    discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound

    def perform(delivery)
      return unless Allure::Federation::Config.enabled?
      Federation::Delivery::Deliver.new(delivery:).call!
    end
  end
end
