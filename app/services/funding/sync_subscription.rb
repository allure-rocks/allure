# frozen_string_literal: true

module Funding
  # Refreshes mutable provider management state from authenticated read-back.
  # No paid contribution is created, extended or revoked here.
  class SyncSubscription
    def self.call(provider:, state:)
      raise ArgumentError, "invalid subscription state" unless state.is_a?(Allure::Funding::SubscriptionState)

      subscription = FundingSubscription.find_by(provider: provider.to_s, external_id: state.subscription_id)
      return create(provider:, state:) unless subscription

      update(subscription, state)
    rescue ActiveRecord::RecordNotUnique
      update(FundingSubscription.find_by!(provider: provider.to_s, external_id: state.subscription_id), state)
    end

    def self.attributes(state)
      {
        customer_id: state.customer_id, tier: state.tier, status: state.status,
        cancel_at_period_end: state.cancel_at_period_end, canceled_at: state.canceled_at,
        synced_at: Time.current
      }
    end
    private_class_method :attributes

    def self.create(provider:, state:)
      FundingSubscription.create!(provider: provider.to_s, external_id: state.subscription_id, **attributes(state))
    end
    private_class_method :create

    def self.update(subscription, state)
      subscription.with_lock { subscription.update!(attributes(state)) }
      subscription
    end
    private_class_method :update
  end
end
