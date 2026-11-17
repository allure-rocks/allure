# frozen_string_literal: true

module Users
  # A ready export is downloadable for AccountExport::LIFETIME; this daily
  # sweep expires the past-due ones and purges their archive
  # (docs/dev/ACCOUNT.md). A job that died mid-build is closed as failed so
  # the account may ask again.
  class AccountExportSweepJob < ApplicationJob
    queue_as :default

    STALE_AFTER = 1.day

    def perform(now: Time.current)
      AccountExport.due_for_expiry(now).find_each(&:expire!)
      AccountExport.in_progress.where(updated_at: ...(now - STALE_AFTER))
        .update_all(status: "failed", error_code: "interrupted", completed_at: now, updated_at: now)
    end
  end
end
