# frozen_string_literal: true

module Users
  # Runs a due account deletion (docs/dev/ACCOUNT.md) in bounded steps:
  # each run deletes at most BATCH workouts and re-enqueues itself while work
  # remains, so a large account never holds one long job or transaction. The
  # final mail goes to the address captured before the row disappears.
  class AccountPurgeJob < ApplicationJob
    queue_as :default
    limits_concurrency key: ->(user_id) { "account-purge-#{user_id}" }, duration: 1.hour
    retry_on Allure::Funding::Providers::ProviderError, wait: :polynomially_longer, attempts: 5

    BATCH = 50

    def perform(user_id)
      user = User.find_by(id: user_id)
      return unless user&.deletion_scheduled? && user.deletion_scheduled_at <= Time.current

      recipient = { email_address: user.email_address, locale: user.locale, username: user.username }
      if DeleteAccount.new(user:, require_scheduled: true).call!(limit: BATCH)
        AccountMailer.deleted(**recipient).deliver_later
      else
        self.class.perform_later(user_id)
      end
    rescue DeleteAccount::Cancelled
      # The account was restored while the purge ran: nothing runs for it, no
      # mail, no re-enqueue.
    end
  end
end
