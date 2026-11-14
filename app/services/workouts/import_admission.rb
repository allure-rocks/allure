# frozen_string_literal: true

module Workouts
  # Whether an account may store another upload (PLAN_IMPORT_SOURCES.md §3.2):
  # a few file imports and one Strava archive waiting at a time, and a bounded
  # number of bytes per day. Counted in the database, so every web process and
  # the API agree; the web and API forms both ask before attaching anything.
  class ImportAdmission
    MAX_ACTIVE_FILE_BATCHES = 3
    MAX_ACTIVE_ARCHIVES = 1
    DAILY_UPLOAD_BYTES = 6.gigabytes
    DAILY_UPLOAD_LABEL = "6 GB"
    WINDOW = 24.hours

    # `reason` is the API's code (PLAN_API.md §5); `message` the form's text;
    # `retry_after` the seconds until the refusal may lift.
    Refusal = Data.define(:reason, :message, :retry_after)

    def initialize(user:, source:, bytes:, now: Time.current)
      @user = user
      @source = source
      @bytes = bytes.to_i
      @now = now
    end

    def refusal
      active_refusal || budget_refusal
    end

    private

    def active_refusal
      active = @user.workout_import_batches.active.where(source: @source).count
      if archive? && active >= MAX_ACTIVE_ARCHIVES
        refuse("archive_in_progress", I18n.t("workouts.batch_import.errors.archive_in_progress"))
      elsif !archive? && active >= MAX_ACTIVE_FILE_BATCHES
        refuse("too_many_active_imports",
               I18n.t("workouts.batch_import.errors.too_many_active_imports", max: MAX_ACTIVE_FILE_BATCHES))
      end
    end

    def budget_refusal
      recent = @user.workout_import_batches.where(created_at: (@now - WINDOW)..)
      return if recent.sum(:source_bytes) + @bytes <= DAILY_UPLOAD_BYTES

      oldest = recent.where(source_bytes: 1..).minimum(:created_at)
      retry_after = oldest ? [ (oldest + WINDOW - @now).ceil, 1 ].max : WINDOW.to_i
      refuse("upload_budget_exceeded",
             I18n.t("workouts.batch_import.errors.upload_budget_exceeded", max: DAILY_UPLOAD_LABEL), retry_after:)
    end

    def refuse(reason, message, retry_after: 60)
      Refusal.new(reason:, message:, retry_after:)
    end

    def archive? = @source == Allure::ImportSources::STRAVA_ARCHIVE.key
  end
end
