# frozen_string_literal: true

module Workouts
  # The review-page summary of a draft operation (PLAN_BULK_ACTIONS.md §4): the
  # exact selection, its date range, sports and publication states, plus the
  # exclusions the operation already knows about, so the owner confirms what
  # will actually happen.
  class BulkReview
    Report = Data.define(
      :workouts, :sports, :started_at_range, :published_count, :scheduled_count,
      :without_original_count, :eligible_count
    ) do
      def count = workouts.size
      def confirmable? = eligible_count.positive?
    end

    def initialize(operation:)
      @operation = operation
    end

    def call
      workouts = @operation.items.in_order
        .includes(workout: [ :sport, { original_file_attachment: :blob } ])
        .filter_map(&:workout)
      # A manual entry has no file and needs none: its sport changes alone
      # (PLAN_MANUAL_ENTRY.md §6).
      without_original = workouts.count { |workout| !workout.manual? && !workout.original_file.attached? }
      published, scheduled = publication_counts(workouts)

      Report.new(
        workouts:,
        sports: sport_breakdown(workouts),
        started_at_range: workouts.filter_map(&:started_at).minmax,
        published_count: published,
        scheduled_count: scheduled,
        without_original_count: without_original,
        eligible_count: @operation.operation == "sport_change" ? workouts.size - without_original : workouts.size
      )
    end

    private

    def sport_breakdown(workouts)
      counts = workouts.group_by(&:sport).transform_values(&:size)
      counts.sort_by { |sport, count| [ -count, sport.label ] }
    end

    def publication_counts(workouts)
      ids = workouts.map(&:id)
      [
        WorkoutPublication.active.where(workout_id: ids).count,
        WorkoutPublication.scheduled.where(workout_id: ids).count
      ]
    end
  end
end
