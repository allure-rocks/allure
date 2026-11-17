# frozen_string_literal: true

module HeartRates
  # Bounded, resumable histogram rebuild for every recording whose marker is
  # older than the current version (PLAN_HEART_RATE.md §3.4,
  # docs/dev/DERIVATIONS.md). The stored points are enough: no original file
  # and no re-analysis.
  class BackfillJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    def self.pending_scope
      Workout.recordings.where(heart_rate_version: ...Allure::HeartRate::Histogram::VERSION)
    end

    def perform(after_id: 0)
      workouts = self.class.pending_scope.where("workouts.id > ?", after_id)
        .includes(:user).order(:id).limit(BATCH_SIZE).to_a
      workouts.each { Rebuild.new(workout: it).call }

      self.class.perform_later(after_id: workouts.last.id) if workouts.length == BATCH_SIZE
    end
  end
end
