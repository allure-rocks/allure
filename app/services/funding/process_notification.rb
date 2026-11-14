# frozen_string_literal: true

module Funding
  # Provider-agnostic order of operations: establish the initial binding,
  # refresh current management state, then record the paid invoice if present,
  # and finally record a reversal signal (PAY-105) against its original payment.
  class ProcessNotification
    def self.call(provider:, notification:)
      raise ArgumentError, "invalid funding notification" unless notification.is_a?(Allure::Funding::Notification)

      BindSubscription.call(provider:, binding: notification.binding) if notification.binding
      SyncSubscription.call(provider:, state: notification.state) if notification.state
      RecordContribution.call(provider:, event: notification.event) if notification.event
      RecordReversal.call(provider:, reversal: notification.reversal) if notification.reversal
      notification
    end
  end
end
