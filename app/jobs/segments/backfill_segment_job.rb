# frozen_string_literal: true

module Segments
  class BackfillSegmentJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(segment, after_id: 0)
      workouts = Segments::CandidateQuery
        .for_segment(segment)
        .where("workouts.id > ?", after_id)
        .limit(BATCH_SIZE)
        .to_a

      workouts.each { |workout| Segments::MatchWorkoutJob.perform_later(workout) }

      last_id = workouts.last&.id
      self.class.perform_later(segment, after_id: last_id) if workouts.length == BATCH_SIZE
    end
  end
end
