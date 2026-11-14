# frozen_string_literal: true

module Allure
  module Funding
    # Only verified adapters construct these values. Provider payloads, names,
    # addresses and card data never cross this boundary.
    Event = Data.define(:kind, :external_id, :tier, :reference, :paid_at, :amount_cents, :currency,
      :subscription_id, :period_start, :period_end)
  end
end
