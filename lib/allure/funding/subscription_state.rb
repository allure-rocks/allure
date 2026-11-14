# frozen_string_literal: true

module Allure
  module Funding
    # Authenticated provider lifecycle facts. This value refreshes management
    # state only; it never grants, extends or revokes a paid contribution.
    SubscriptionState = Data.define(:subscription_id, :customer_id, :tier, :status,
      :cancel_at_period_end, :canceled_at)
  end
end
