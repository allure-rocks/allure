# frozen_string_literal: true

module Allure
  module Funding
    # The provider-verified initial checkout facts used once to bind an account.
    # `created_at` comes from the provider, never from browser parameters.
    CheckoutBinding = Data.define(:subscription_id, :customer_id, :tier, :reference, :created_at)
  end
end
