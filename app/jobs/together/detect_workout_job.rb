# frozen_string_literal: true

module Together
  # Looks for the account's partners on the same outing after an import
  # (docs/dev/SHARED-ACTIVITIES.md).
  class DetectWorkoutJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    def perform(workout)
      Detection.call(workout)
    end
  end
end
