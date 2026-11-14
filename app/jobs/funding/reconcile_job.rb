# frozen_string_literal: true

module Funding
  # Recurring recovery for lost or reordered provider notifications
  # (PLAN_FUNDING.md §6.7). Idempotent recording makes a replay harmless.
  class ReconcileJob < ApplicationJob
    queue_as :default

    # A month of grace beyond an annual renewal date.
    WINDOW = 32.days

    def perform
      return unless Allure::Funding.enabled?

      Allure::Funding::Providers.enabled.each do |provider|
        Funding::Reconcile.call(provider:, since: WINDOW.ago)
      end
    end
  end
end
