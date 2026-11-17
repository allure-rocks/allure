# frozen_string_literal: true

module Notifications
  # Pushes one notification to the recipient's devices (docs/dev/PUSH.md).
  # Enqueued once per alert, it fans out into one job per subscription, so a
  # retry only ever resends to the device that failed. Nothing happens while
  # push is unconfigured, nor for a notification already read or gone.
  #
  # A 2xx records the success; a 404/410 or a 403 `key_mismatch` deletes the
  # subscription; any other
  # 4xx is final for this push; a 429, a 5xx or no answer retries with
  # back-off. Every failure counts, and ten in a row delete the subscription.
  class PushJob < ApplicationJob
    class RetryableFailure < StandardError; end

    RESULTS = %w[delivered gone rejected failed].freeze

    queue_as :default

    retry_on RetryableFailure, wait: :polynomially_longer, attempts: 5 do |_job, _error|
      # The failures are already counted on the subscription; the push is
      # given up.
    end

    # Called by the producers inside their transaction: the job waits for the
    # commit, so a rolled-back notification is never pushed.
    def self.enqueue_after_commit(notification)
      return unless notification && Allure::Push::Config.enabled?
      return unless notification.user.push_subscriptions.exists?

      notification_id = notification.id
      ActiveRecord.after_all_transactions_commit { perform_later(notification_id) }
    end

    def perform(notification_id, subscription_id = nil, delivery: PushDelivery.new)
      return unless Allure::Push::Config.enabled?

      notification = Notification.includes(:user).find_by(id: notification_id)
      return if notification.nil? || notification.read? || notification.user.deactivated?

      if subscription_id.nil?
        notification.user.push_subscriptions.ids.each { |id| self.class.perform_later(notification_id, id) }
      else
        subscription = notification.user.push_subscriptions.find_by(id: subscription_id)
        push(notification, subscription, delivery) if subscription
      end
    end

    private

    def push(notification, subscription, delivery)
      plaintext = PushPayload.new(notification:, subscription:).to_json
      outcome = delivery.deliver(subscription, plaintext)
      if outcome.success?
        subscription.record_success!
        count("delivered")
      elsif outcome.gone?
        subscription.destroy!
        count("gone")
      elsif outcome.retryable?
        count("failed")
        raise RetryableFailure, outcome.error.to_s unless subscription.record_failure!
      else
        count("rejected")
        subscription.record_failure!
      end
    end

    def count(result)
      Yabeda.allure.push_deliveries_total.increment({ result: })
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: "push_deliveries_total" })
    end
  end
end
