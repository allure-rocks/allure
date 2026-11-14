# frozen_string_literal: true

module ApiTokens
  # Revoked and expired tokens stay listed for 90 days, then go
  # (PLAN_API.md §4.1); stored idempotent responses go after 24 hours (§5).
  class PruneJob < ApplicationJob
    queue_as :default

    def perform(now: Time.current)
      ApiToken.prunable(now).in_batches(of: 1_000).delete_all
      ApiIdempotencyKey.expired(now).in_batches(of: 1_000).delete_all
    end
  end
end
