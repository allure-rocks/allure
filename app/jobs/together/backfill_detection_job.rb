# frozen_string_literal: true

module Together
  # Bounded, resumable co-presence detection over the recordings the current
  # detector has not compared yet (docs/dev/SHARED-ACTIVITIES.md), launched and
  # audited from /admin/jobs. Each recording is detected by its own job, which
  # stamps the version, so a rerun only finds what is left; a pair is
  # suggested once whichever side runs first.
  class BackfillDetectionJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    # Co-presence compares tracks, so a positionless recording is out of
    # scope entirely (PLAN_NO_GPS.md §6).
    def self.pending_scope
      Workout.positioned.where(together_detection_version: ...Allure::Together::Detector::VERSION)
    end

    def perform(after_id: 0)
      workouts = self.class.pending_scope.where("workouts.id > ?", after_id).order(:id).limit(BATCH_SIZE).to_a
      workouts.each { |workout| DetectWorkoutJob.perform_later(workout) }

      self.class.perform_later(after_id: workouts.last.id) if workouts.length == BATCH_SIZE
    end
  end
end
