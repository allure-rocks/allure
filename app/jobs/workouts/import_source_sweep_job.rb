# frozen_string_literal: true

module Workouts
  # Frees the uploads no import will read again (docs/dev/IMPORT-SOURCES.md):
  # those of every finished batch the batch jobs did not release themselves,
  # and those of an uploaded batch that made no progress for `STALLED_AFTER`,
  # which is failed first so it never resumes without its files.
  class ImportSourceSweepJob < ApplicationJob
    STALLED_AFTER = 7.days
    UPLOADED_SOURCES = [ "file", Allure::ImportSources::STRAVA_ARCHIVE.key ].freeze
    BATCH_SIZE = 200

    queue_as :default

    def perform(now: Time.current)
      fail_stalled(now)
      with_uploads(WorkoutImportBatch.terminal).find_each(batch_size: BATCH_SIZE, &:release_sources!)
    end

    private

    def fail_stalled(now)
      stalled = WorkoutImportBatch.active.where(source: UPLOADED_SOURCES, updated_at: ...(now - STALLED_AFTER))
      stalled.includes(:user).find_each(batch_size: BATCH_SIZE) do |batch|
        message = I18n.with_locale(batch.user.locale) { I18n.t("workouts.batch_import.errors.stalled") }
        batch.entries.where(status: %w[queued processing]).update_all(
          status: "failed", error_message: message, completed_at: now, updated_at: now
        )
        batch.refresh_progress!
        batch.update_columns(status: "failed", error_message: message, completed_at: now, updated_at: now)
      end
    end

    def with_uploads(scope)
      scope.where(id: ActiveStorage::Attachment.where(record_type: WorkoutImportBatch.name, name: "source_files")
                                               .select(:record_id))
    end
  end
end
