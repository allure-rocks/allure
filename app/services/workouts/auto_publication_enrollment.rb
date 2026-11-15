# frozen_string_literal: true

module Workouts
  # Called by the importer once a new workout is persisted
  # (docs/dev/AUTO-PUBLISHING.md). For every automatic publishing profile of the
  # account it records one ledger row: `waiting` for the enrichments, or
  # `skipped` straight away when the import itself rules the publication out
  # (a bulk import, an activity older than the recent window, an excluded
  # commute or sport). Only profiles automatic at import time count, so
  # enabling the option never publishes an earlier workout.
  class AutoPublicationEnrollment
    def initialize(workout:, bulk: false, now: Time.current)
      @workout = workout
      @bulk = bulk
      @now = now
    end

    def call
      profiles = @workout.user.publishing_profiles.automatic.order(:position, :id).to_a
      return [] if profiles.empty?

      rows = profiles.uniq(&:audience).map { |profile| enroll(profile) }
      AutoPublishJob.nudge(@workout) if rows.any?(&:waiting?)
      rows
    end

    private

    def enroll(profile)
      reason = skip_reason(profile)
      @workout.auto_publications.create!(
        publishing_profile: profile,
        audience: profile.audience,
        status: reason ? "skipped" : "waiting",
        reason:,
        deadline_at: @now + WorkoutAutoPublication::ENRICHMENT_DEADLINE,
        settled_at: (@now if reason)
      )
    end

    def skip_reason(profile)
      return "bulk_import" if @bulk
      return "stale" if @workout.started_at < @now - WorkoutAutoPublication::RECENT_WINDOW
      return "commute" if @workout.commute? && profile.auto_publish_exclude_commute?
      return "sport" if profile.auto_publish_excludes_sport?(@workout.sport)
      return "profile_unavailable" unless profile.publishable?
      # A positionless recording cannot be published at all, so it never
      # waits on enrichments that will not run (PLAN_NO_GPS.md §7).
      return "no_geometry" unless @workout.positioned?

      nil
    end
  end
end
