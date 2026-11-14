# frozen_string_literal: true

module Workouts
  class ReanalyzeJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, ActiveStorage::FileNotFoundError,
             wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    # `elevation_source:` forces the source applied by this run and implies
    # `force: true`; without it the workout's effective source is reused.
    def perform(workout, elevation_source = nil)
      Workouts::Reanalyzer.new(workout:, force: elevation_source.present?, elevation_source:).call!
      # Reanalysis rewrites track segments and recorded laps, which invalidates
      # every point-indexed effort and detected lap. Re-matching rebuilds both
      # from the fresh geometry.
      Segments::MatchWorkoutJob.perform_later(workout)
    end
  end
end
