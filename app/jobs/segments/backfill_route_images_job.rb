# frozen_string_literal: true

module Segments
  # Re-renders every owner segment image whose stored renderer generation is
  # older than the current one, or that was never rendered
  # (docs/dev/DERIVATIONS.md). Bounded id-cursor batches that resume themselves on the low-concurrency
  # `route_images` worker. Publication images are snapshot media and are
  # deliberately out of scope.
  class BackfillRouteImagesJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    class << self
      def pending_scope
        Segment.where(route_image_version: ...RouteImage::VERSION)
      end
    end

    def perform(after_id: 0)
      segments = self.class.pending_scope
        .where("segments.id > ?", after_id)
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a

      segments.each { |segment| RenderRouteImageJob.perform_later(segment) }

      self.class.perform_later(after_id: segments.last.id) if segments.length == BATCH_SIZE
    end
  end
end
