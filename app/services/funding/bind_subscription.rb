# frozen_string_literal: true

module Funding
  # Resolves the initial signed checkout reference at the provider-verified
  # checkout creation time. Existing matches always win over a later reference.
  #
  # A verified reference also binds an account whose deletion is scheduled
  # (billing-lifecycle ownership, never a badge: the account is deactivated,
  # so every benefit surface stays hidden), so a late initial notification
  # cannot orphan a renewing subscription at purge. Once the deletion has
  # started it can no longer be cancelled, so the renewal is stopped at the
  # provider immediately and durably.
  class BindSubscription
    def self.call(provider:, binding:)
      raise ArgumentError, "invalid checkout binding" unless binding.is_a?(Allure::Funding::CheckoutBinding)

      provider = provider.to_s
      user = resolve_user(binding)
      subscription = FundingSubscription.find_by(provider:, external_id: binding.subscription_id)
      unless subscription
        create(provider:, binding:, user:) rescue ActiveRecord::RecordNotUnique
        subscription = FundingSubscription.find_by!(provider:, external_id: binding.subscription_id)
      end
      attach_or_keep(subscription, user)
      stop_renewal_if_deletion_started(subscription, user)
      subscription
    end

    def self.create(provider:, binding:, user:)
      FundingSubscription.create!(
        provider:, external_id: binding.subscription_id, customer_id: binding.customer_id,
        tier: binding.tier, user:, status: "incomplete"
      )
    end
    private_class_method :create

    def self.resolve_user(binding)
      return unless binding.created_at

      Funding::Reference.resolve(binding.reference, tier: binding.tier, at: binding.created_at, for_billing: true)
    end
    private_class_method :resolve_user

    def self.attach_or_keep(subscription, user)
      return subscription unless user && subscription.user_id.nil?

      if user.deletion_scheduled?
        attach_billing_owner(subscription, user)
      else
        AttachSubscription.call(subscription:, user:)
      end
      subscription
    end
    private_class_method :attach_or_keep

    # Claims the subscription and its unmatched paid invoices for an account
    # whose deletion is scheduled, without the benefit path (no badge while
    # deactivated, no notification): the purge cancels the renewal through
    # the matched association, and a cancelled deletion restores the periods.
    def self.attach_billing_owner(subscription, user)
      FundingSubscription.transaction do
        subscription.lock!
        next subscription if subscription.user_id == user.id
        raise ActiveRecord::RecordInvalid, subscription if subscription.user_id.present?

        subscription.update!(user:)
        subscription.funding_contributions.where(user_id: nil).find_each do |contribution|
          contribution.update!(user:)
        end
      end
      subscription
    end
    private_class_method :attach_billing_owner

    # After the cut-off the purge's own cancellation step may already have
    # run: stop the renewal now. The binding above is committed first, so a
    # provider failure raises and the webhook retries instead of orphaning a
    # renewing subscription.
    def self.stop_renewal_if_deletion_started(subscription, user)
      return unless user&.deletion_started? && subscription.user_id == user.id && subscription.live?

      CancelSubscriptions.cancel_one(subscription)
    end
    private_class_method :stop_renewal_if_deletion_started
  end
end
