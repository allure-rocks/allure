# frozen_string_literal: true

module Workouts
  # The single server-side way to (re)schedule a workout's geocoding
  # (PLAN_DERIVATIONS.md §4). It marks the toponymy pending, so the enricher
  # does not short-circuit on a row that is still `ready` for the previous
  # geometry, and enqueues the globally paced job. Nothing reads the owner's
  # page to decide this any more: imports, re-analyses, the elevation apply
  # job, the sweeps and the recovery job call it.
  #
  # A virtual workout is never geocoded; a legacy row is discarded instead
  # (docs/dev/VIRTUAL-PLATFORMS.md).
  class ToponymyRefresh
    def initialize(workout:)
      @workout = workout
    end

    def call
      if @workout.sport.virtual?
        @workout.toponymy&.destroy!
        return nil
      end

      toponymy = mark_pending
      enqueue(toponymy)
      toponymy
    end

    private

    def mark_pending
      toponymy = @workout.toponymy || @workout.create_toponymy!(
        status: "pending",
        algorithm_version: ToponymyEnricher::ALGORITHM_VERSION
      )
      toponymy.update!(status: "pending", updated_at: Time.current)
      toponymy
    rescue ActiveRecord::RecordNotUnique
      @workout.association(:toponymy).reload
      retry
    end

    def enqueue(toponymy)
      EnrichToponymyJob.perform_later(@workout)
    rescue StandardError => error
      toponymy.update_columns(status: "failed", last_error: error.message.to_s.truncate(500), updated_at: Time.current)
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: @workout.id })
    end
  end
end
