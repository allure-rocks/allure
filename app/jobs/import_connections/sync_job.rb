# frozen_string_literal: true

module ImportConnections
  # The sync of one connection (PLAN_REMOTE_IMPORTS.md §6.1): lists the window
  # since the last sync, minus a day for late uploads, and creates a batch only
  # when something new remains. The hourly sweep only enqueues connections with
  # automatic sync; « Synchroniser maintenant » asks for the same pass with
  # `manual: true`, so it works whatever the preference says, and its batch is
  # marked `manual`.
  class SyncJob < ApplicationJob
    OVERLAP = 24.hours

    queue_as :remote_imports

    limits_concurrency key: ->(connection, **) { connection.id.to_s }, group: ImportConnection::CONCURRENCY_GROUP,
                       duration: 30.minutes

    def perform(connection, now: Time.current, manual: false)
      return unless connection.usable? && (manual || connection.auto_sync?) && !connection.user.deactivated?

      I18n.with_locale(connection.user.locale) do
        activities = Providers.for(connection).list(from: window_start(connection, now), to: now)
        enqueue_batch(connection, activities, now, trigger: manual ? "manual" : "scheduled")
        connection.update!(last_synced_at: now, last_sync_error: nil)
      rescue Allure::RemoteImports::Error::SessionEnded
        Expiry.new(connection, notify: false).call
      rescue Allure::RemoteImports::Error::AuthError
        Expiry.new(connection).call
      rescue Allure::RemoteImports::Error
        connection.update!(last_sync_error: I18n.t("settings.connections.errors.unavailable"))
      end
    end

    private

    def window_start(connection, now)
      [ connection.last_synced_at || now, now ].min - OVERLAP
    end

    def enqueue_batch(connection, activities, now, trigger:)
      batch = nil
      WorkoutImportBatch.transaction do
        batch = connection.user.workout_import_batches.create!(
          source: connection.provider, import_connection: connection, trigger:, discovered_at: now
        )
        created = Workouts::RemoteImportEntries.new(batch:, connection:).add(activities, drop_known: true)
        if created.zero?
          batch.destroy!
          batch = nil
        end
      end
      return unless batch

      batch.refresh_progress!
      Workouts::RemoteImportBatchJob.perform_later(batch)
    end
  end
end
