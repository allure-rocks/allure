# frozen_string_literal: true

module Segments
  # Geocodes the nearby place of every course still pending or failed
  # (PLAN_SEGMENTS.md §8.4, PLAN_DERIVATIONS.md §5). Bounded id-cursor batches
  # that resume themselves; each course goes through the paced geocoding job.
  class BackfillPlacesJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    class << self
      def pending_scope
        Segment.where(place_status: %w[pending failed])
      end
    end

    def perform(after_id: 0)
      return unless Allure::Toponyms::Config.configured?

      segments = self.class.pending_scope
        .where("segments.id > ?", after_id)
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a

      segments.each { |segment| GeocodePlaceJob.perform_later(segment, force: true) }

      self.class.perform_later(after_id: segments.last.id) if segments.length == BATCH_SIZE
    end
  end
end
