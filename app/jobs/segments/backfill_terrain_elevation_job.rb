# frozen_string_literal: true

module Segments
  # Gives every eligible course the terrain service's elevation figures
  # (PLAN_ELEVATION.md §10, PLAN_DERIVATIONS.md §5): those never tried and
  # those whose last try failed. Bounded id-cursor batches that resume
  # themselves; each course goes through its own job, paced by the provider
  # throttle. `user_id` narrows the sweep to one account, when it consents.
  class BackfillTerrainElevationJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    class << self
      def pending_scope
        TerrainElevation.pending_scope
      end
    end

    def perform(after_id: 0, user_id: nil)
      return unless Allure::Elevation::Config.configured?

      scope = self.class.pending_scope.where("segments.id > ?", after_id)
      scope = scope.where(user_id:) if user_id
      segments = scope.order(:id).limit(BATCH_SIZE).to_a

      segments.each { |segment| ApplyTerrainElevationJob.perform_later(segment) }

      self.class.perform_later(after_id: segments.last.id, user_id:) if segments.length == BATCH_SIZE
    end
  end
end
