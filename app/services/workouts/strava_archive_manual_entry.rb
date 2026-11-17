# frozen_string_literal: true

module Workouts
  # An archive row without a file — an activity typed in by hand on Strava —
  # becomes a manual entry (docs/dev/STRAVA-ARCHIVE.md,
  # docs/dev/MANUAL-ENTRY.md) through `Workouts::ManualEntry`, the single write
  # seam. The start comes from the localized `Activity Date` (UTC), the
  # figures from the row's SI block. A figure a manual entry would refuse
  # (outside `Workout::MANUAL_LIMITS`, an ascent for a sport that measures
  # none) is left out rather than refusing the activity; a row without a
  # readable start or a duration is refused with its reason.
  class StravaArchiveManualEntry
    class Unreadable < StandardError; end

    def initialize(user:, metadata:, sport:, equipment_ids: nil)
      @user = user
      @metadata = metadata
      @sport = sport
      @figures = metadata.fetch("figures", {})
      @equipment_ids = equipment_ids
    end

    def started_at
      @started_at ||= Allure::StravaArchive::Dates.parse(@metadata["date"]) ||
                      raise(Unreadable, I18n.t("workouts.batch_import.errors.unreadable_strava_date",
                                               date: @metadata["date"].to_s))
    end

    def call
      ManualEntry.create(user: @user, attributes:, equipment_ids: @equipment_ids)
    end

    private

    def attributes
      duration = within(:duration, @figures["elapsed"]&.round)
      raise Unreadable, I18n.t("workouts.batch_import.errors.missing_strava_duration") unless duration

      moving = within(:moving_time, @figures["moving"]&.round)
      {
        sport: @sport,
        started_at:,
        duration:,
        moving_time: moving && [ moving, duration ].min,
        distance: within(:distance, @figures["distance"]),
        ascent: (within(:ascent, @figures["ascent"]) if @sport.records_elevation),
        average_heart_rate: within(:average_heart_rate, @figures["average_heart_rate"]&.round),
        max_heart_rate: max_heart_rate,
        calories: within(:calories, @figures["calories"]&.round),
        average_power: within(:average_power, @figures["average_power"]&.round),
        title: @metadata["name"]&.truncate(StravaArchiveImportJob::TITLE_LENGTH),
        description: @metadata["description"]&.truncate(StravaArchiveImportJob::DESCRIPTION_LENGTH),
        notes: @metadata["private_note"]&.truncate(StravaArchiveImportJob::NOTES_LENGTH),
        commute: @metadata["commute"] == true
      }.compact
    end

    # A maximum under the average would refuse the entry; it is dropped.
    def max_heart_rate
      max = within(:max_heart_rate, @figures["max_heart_rate"]&.round)
      average = within(:average_heart_rate, @figures["average_heart_rate"]&.round)
      max if max && (average.nil? || max >= average)
    end

    def within(attribute, value)
      value if value && Workout::MANUAL_LIMITS.fetch(attribute).cover?(value)
    end
  end
end
