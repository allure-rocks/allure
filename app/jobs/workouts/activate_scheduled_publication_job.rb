# frozen_string_literal: true

module Workouts
  # Runs at `scheduled_for` and activates the publication
  # (docs/dev/DELAYED-PUBLISHING.md). A job that fires before the planned moment —
  # because the owner rescheduled — defers itself; a lost job is recovered by
  # the recurring sweep in Federation::RecoveryJob.
  class ActivateScheduledPublicationJob < ApplicationJob
    queue_as :default

    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(publication)
      Workouts::ScheduledPublicationActivation.new(publication:).call!
    end
  end
end
