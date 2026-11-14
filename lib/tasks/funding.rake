# frozen_string_literal: true

namespace :funding do
  # The safety net for lost or reordered provider webhooks
  # (PLAN_FUNDING.md §6.7). Without `SINCE`, every paid provider invoice is
  # replayed; idempotency makes that harmless.
  desc "Replay paid funding invoices through each enabled provider's recovery seam"
  task reconcile: :environment do
    abort "Funding is disabled." unless Allure::Funding.enabled?
    providers = Allure::Funding::Providers.enabled
    abort "No funding provider is enabled." if providers.empty?

    since = ENV["SINCE"]&.then { |value| Time.zone.parse(value) }
    providers.each do |provider|
      processed = Funding::Reconcile.call(provider:, since:)
      puts "#{provider.slug}: #{processed} paid invoice#{processed == 1 ? "" : "s"} processed"
    end
  end
end
