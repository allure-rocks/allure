# frozen_string_literal: true

module Segments
  # Fills the stored elevation profile of every source-backed segment that does
  # not have one yet (docs/dev/DERIVATIONS.md). Bounded id-cursor batches that
  # resume themselves; a segment whose source workout was deleted, or whose
  # provenance no longer matches, is stamped [] by the build job and never
  # revisited.
  class BackfillElevationProfilesJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    class << self
      def pending_scope
        Segment.where(elevation_profile: nil).where.not(source_workout_id: nil)
      end
    end

    def perform(after_id: 0)
      segments = self.class.pending_scope
        .where("segments.id > ?", after_id)
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a

      segments.each { |segment| BuildElevationProfileJob.perform_later(segment) }

      self.class.perform_later(after_id: segments.last.id) if segments.length == BATCH_SIZE
    end
  end
end
