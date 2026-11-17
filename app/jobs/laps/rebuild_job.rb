# frozen_string_literal: true

module Laps
  # Derives the smart laps of one workout from its stored points
  # (docs/dev/SMART-LAPS.md). The segment-matching job runs the same rebuild for a
  # positioned workout; a positionless recording, whose points carry no
  # geometry to match against, reaches it through this job instead
  # (docs/dev/NO-GPS.md).
  class RebuildJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, ActiveRecord::RecordNotUnique,
             wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(workout)
      Laps::Rebuild.new(workout:).call
      Records::RecomputeService.new(user: workout.user, sport: workout.sport).call
    end
  end
end
