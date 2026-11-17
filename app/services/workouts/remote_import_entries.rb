# frozen_string_literal: true

module Workouts
  # Turns a provider listing into the entries of a remote batch
  # (docs/dev/REMOTE-IMPORTS.md). Idempotent: an activity already listed in
  # the batch is left alone, so a listing interrupted by the quota resumes.
  #
  # An activity without geometry is `skipped` at once, and one the connection
  # already imported is a `duplicate` of its workout; with `drop_known: true`
  # (the scheduled sync) known activities are left out instead of reported,
  # and so is anything an earlier batch of the connection already settled or
  # still holds — only a failed or cancelled entry is tried again.
  class RemoteImportEntries
    def initialize(batch:, connection:)
      @batch = batch
      @connection = connection
    end

    # Returns the number of entries created.
    def add(activities, drop_known: false)
      activities = Array(activities)
      known = known_workouts(activities)
      listed = drop_known ? listed_elsewhere(activities) : Set.new
      created = 0

      activities.each do |activity|
        workout = known[activity.external_id.to_s]
        next if drop_known && (workout || listed.include?(activity.external_id.to_s))

        entry = @batch.entries.create_or_find_by!(source_key: source_key(activity)) do |record|
          record.position = next_position
          record.source_name = source_name(activity)
          record.external_id = activity.external_id.to_s
          record.metadata = activity.metadata
          assign_outcome(record, activity, workout)
        end
        created += 1 if entry.previously_new_record?
      end
      created
    end

    private

    def assign_outcome(record, activity, workout)
      now = Time.current
      if workout
        record.assign_attributes(status: "duplicate", workout:, completed_at: now)
      elsif activity.manual
        # The provider holds a manual entry with no file at all; an indoor
        # activity without a GPS track keeps its file and is imported
        # positionlessly (docs/dev/NO-GPS.md).
        record.assign_attributes(status: "skipped", skip_reason: "no_file", completed_at: now)
      else
        record.status = "queued"
      end
    end

    def known_workouts(activities)
      ids = activities.map { |activity| activity.external_id.to_s }
      @connection.workouts.where(external_id: ids).index_by(&:external_id)
    end

    def listed_elsewhere(activities)
      WorkoutImportEntry.joins(:batch)
        .where(workout_import_batches: { import_connection_id: @connection.id })
        .where.not(batch_id: @batch.id)
        .where.not(status: %w[failed cancelled])
        .where(external_id: activities.map { |activity| activity.external_id.to_s })
        .distinct.pluck(:external_id).to_set
    end

    def source_key(activity) = "remote:#{activity.external_id}"

    def source_name(activity)
      name = activity.name.to_s.strip
      name = I18n.t("workouts.batch_import.remote.untitled", id: activity.external_id) if name.empty?
      name.truncate(255)
    end

    def next_position
      @batch.entries.maximum(:position)&.next || 0
    end
  end
end
