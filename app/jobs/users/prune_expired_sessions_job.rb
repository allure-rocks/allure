# frozen_string_literal: true

module Users
  # An expired session is refused on its next request; this daily sweep removes
  # the rows of browsers that never come back (PLAN_AUTH.md §8), with the iOS
  # companion's uncollected provider handoffs (§9).
  class PruneExpiredSessionsJob < ApplicationJob
    queue_as :default

    def perform(now: Time.current)
      Session.expired(now).in_batches(of: 1_000).delete_all
      SessionHandoff.expired(now).delete_all
    end
  end
end
