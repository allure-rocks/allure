# frozen_string_literal: true

namespace :remote_imports do
  # One pass of the hourly sync (PLAN_REMOTE_IMPORTS.md §6.1), run here
  # instead of spread over the hour: every linked connection with automatic
  # sync lists the window since its last sync and queues what is new.
  desc "Synchronise every linked remote import connection now"
  task sync: :environment do
    providers = Allure::RemoteImports::Config.enabled_providers
    abort "No remote import source is enabled." if providers.empty?

    ImportConnection.linked.where(auto_sync: true, provider: providers).find_each do |connection|
      ImportConnections::SyncJob.perform_now(connection)
      connection.reload
      puts "@#{connection.user.username} #{connection.provider}: #{connection.status}" \
           "#{", #{connection.last_sync_error}" if connection.last_sync_error.present?}"
    end
  end
end
