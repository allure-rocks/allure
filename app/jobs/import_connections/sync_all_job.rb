# frozen_string_literal: true

module ImportConnections
  # Every hour (config/recurring.yml): one sync per linked connection with
  # automatic sync, spread over the hour so the providers never see a burst.
  class SyncAllJob < ApplicationJob
    SPREAD = 50.minutes

    queue_as :remote_imports

    def perform
      providers = Allure::RemoteImports::Config.enabled_providers
      return if providers.empty?

      scope = ImportConnection.linked.where(auto_sync: true, provider: providers)
        .joins(:user).where(users: { suspended_at: nil, deletion_scheduled_at: nil })
      count = scope.count
      scope.order(:id).each_with_index do |connection, index|
        SyncJob.set(wait: (SPREAD * index / count)).perform_later(connection)
      end
    end
  end
end
