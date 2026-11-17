# frozen_string_literal: true

module Users
  # Hourly: starts the purge of every account whose deletion window has ended,
  # and resumes any purge that stopped half-way (docs/dev/ACCOUNT.md). The
  # purge job's concurrency key keeps one run per account.
  class AccountDeletionSweepJob < ApplicationJob
    queue_as :default

    def perform(now: Time.current)
      User.deletion_due(now).pluck(:id).each { AccountPurgeJob.perform_later(it) }
    end
  end
end
