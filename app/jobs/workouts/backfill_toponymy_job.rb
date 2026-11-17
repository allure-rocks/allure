# frozen_string_literal: true

module Workouts
  # Re-geocodes, in bounded id-cursor batches that resume themselves, every
  # workout whose toponymy is missing or was built by an older
  # `ToponymyEnricher::ALGORITHM_VERSION`, and discards a legacy toponymy left
  # on a virtual workout (docs/dev/DERIVATIONS.md). It only schedules: the
  # geocoding job is globally paced. A version change the enricher can
  # re-derive from the stored samples is re-selected offline, so the sweep only
  # pays the reverse requests it must. A workout still waiting for its terrain
  # elevation is left to the re-analysis that applies it.
  class BackfillToponymyJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    class << self
      # A credit row and a positionless recording have no track to geocode
      # (docs/dev/SHARED-ACTIVITIES.md, docs/dev/NO-GPS.md).
      def pending_scope
        stale = Workout.positioned
          .joins(:sport)
          .left_joins(:toponymy)
          .where(sports: { virtual: false }, elevation_source_requested: nil)
          .where(
            "workout_toponymies.id IS NULL OR workout_toponymies.algorithm_version < ?",
            ToponymyEnricher::ALGORITHM_VERSION
          )
        legacy_virtual = Workout.joins(:sport, :toponymy).where(sports: { virtual: true })

        Workout.where(id: stale.select(:id)).or(Workout.where(id: legacy_virtual.select(:id)))
      end
    end

    def perform(after_id: 0)
      workouts = self.class.pending_scope
        .where("workouts.id > ?", after_id)
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a
      workouts.each { |workout| ToponymyRefresh.new(workout:).call }

      self.class.perform_later(after_id: workouts.last.id) if workouts.length == BATCH_SIZE
    end
  end
end
