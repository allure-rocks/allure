# frozen_string_literal: true

module Allure
  module Funding
    # One authenticated provider notification. Binding and state are applied
    # before its optional payment/refund event, so an invoice may arrive before
    # Stripe's checkout notification without losing its durable account link.
    # A reversal (refund/dispute signal, PAY-105) is applied after them and
    # never grants or revokes anything by itself.
    Notification = Data.define(:event, :binding, :state, :reversal)
  end
end
