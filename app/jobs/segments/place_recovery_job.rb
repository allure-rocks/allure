# frozen_string_literal: true

module Segments
  # Recurring recovery for course places (PLAN_DERIVATIONS.md §4): reschedules
  # a course left pending past any plausible queue wait (a lost job) and a
  # recent failure. Older rows — legacy courses included — are left to the
  # operator's sweep, so a place the provider cannot name is not asked about
  # forever.
  class PlaceRecoveryJob < ApplicationJob
    LIMIT = 200
    PENDING_RETRY_AFTER = 2.hours
    FAILED_RETRY_AFTER = 6.hours
    RECENT = 2.days

    queue_as :default

    class << self
      def pending_scope(now: Time.current)
        stuck = Segment.where(place_status: "pending", created_at: (now - RECENT)...(now - PENDING_RETRY_AFTER))
        failed = Segment.where(
          place_status: "failed",
          place_geocoded_at: ...(now - FAILED_RETRY_AFTER),
          created_at: (now - RECENT)..
        )
        stuck.or(failed)
      end
    end

    def perform
      return unless Allure::Toponyms::Config.configured?

      self.class.pending_scope.order(:id).limit(LIMIT).each do |segment|
        GeocodePlaceJob.perform_later(segment, force: true)
      end
    end
  end
end
