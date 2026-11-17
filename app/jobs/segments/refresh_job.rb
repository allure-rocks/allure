# frozen_string_literal: true

module Segments
  # Refreshes the segments a deleted workout had efforts on
  # (docs/dev/SHARED-ACTIVITIES.md). Deleting a workout cascades its efforts away; without this, the
  # segments' counters and personal-best flags kept counting them. A segment
  # deleted in the meantime is simply skipped.
  class RefreshJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             wait: :polynomially_longer, attempts: 5

    def perform(segment_ids)
      Segment.where(id: segment_ids).find_each { |segment| Segments::Refresh.call(segment) }
    end
  end
end
