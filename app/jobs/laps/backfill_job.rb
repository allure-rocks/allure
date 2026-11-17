# frozen_string_literal: true

module Laps
  # Bounded, resumable rebuild of detected laps for every existing workout.
  # Workouts predate the detector, and their tracks are immutable, so a plain
  # rebuild is enough; no re-matching is needed. Records are recomputed once per
  # affected (user, sport) at the end of each batch so derived records (the
  # biggest climb) pick up the rebuilt rows.
  class BackfillJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    def perform(after_id: 0)
      # A credit row has no track and no laps (docs/dev/SHARED-ACTIVITIES.md).
      workouts = Workout.recordings.where("id > ?", after_id).order(:id).limit(BATCH_SIZE).to_a
      workouts.each do |workout|
        Laps::Rebuild.new(workout:).call
        Participations::CreditSyncJob.nudge(workout)
      end

      recompute_records(workouts)

      last_id = workouts.last&.id
      self.class.perform_later(after_id: last_id) if workouts.length == BATCH_SIZE
    end

    private

    def recompute_records(workouts)
      workouts.map { |workout| [ workout.user_id, workout.sport_id ] }.uniq.each do |user_id, sport_id|
        user = User.find_by(id: user_id)
        sport = Sport.find_by(id: sport_id)
        Records::RecomputeService.new(user:, sport:).call if user && sport
      end
    end
  end
end
