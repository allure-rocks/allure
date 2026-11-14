# frozen_string_literal: true

module Allure
  module Funding
    # One verified reversal signal (refund or dispute) against an original
    # paid invoice. Only verified adapters construct these values;
    # `payment_external_id` is the original invoice identity the reversal
    # resolves to through the provider's own relationships.
    Reversal = Data.define(:kind, :external_id, :status, :amount_cents, :currency, :reported_at, :payment_external_id)
  end
end
