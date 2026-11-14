# frozen_string_literal: true

module Funding
  # Account-deletion safeguard. It deliberately ignores FUNDING_ENABLED: the
  # display switch must never leave an external subscription charging after
  # the account and its provider identifiers have been purged.
  class CancelSubscriptions
    def self.call(user:)
      user.funding_subscriptions.live.find_each do |subscription|
        cancel_one(subscription)
      end
    end

    # One provider cancellation with durable state sync. Raises
    # ProviderError when no adapter can cancel, so the caller (the purge or
    # a late webhook) retries instead of silently leaving a renewal live.
    def self.cancel_one(subscription)
      provider = Allure::Funding::Providers.registered(subscription.provider)
      unless provider&.respond_to?(:cancel)
        raise Allure::Funding::Providers::ProviderError, "no cancellation adapter for #{subscription.provider}"
      end

      state = provider.cancel(subscription:)
      SyncSubscription.call(provider: subscription.provider, state:) if state
    end
  end
end
