# frozen_string_literal: true

module HeartRates
  # Re-slices an account's histograms under its current zones after the
  # heart-rate profile changes (docs/dev/HEART-RATE.md), or clears the zone
  # columns when the profile is gone. Reads no point. Rows already sliced
  # under the current fingerprint are left alone, so a re-run is a no-op.
  class RezoneJob < ApplicationJob
    BATCH_SIZE = 200

    queue_as :default

    limits_concurrency to: 1, key: ->(user) { "heart-rate-rezone-#{user.id}" }, duration: 15.minutes

    def perform(user)
      zones = user.heart_rate_zones
      scope = WorkoutHeartRate.joins(:workout).where(workouts: { user_id: user.id })
      scope = zones ? stale_under(scope, zones) : scope.where.not(zones_fingerprint: nil)

      scope.in_batches(of: BATCH_SIZE) do |batch|
        batch.each do |row|
          row.assign_zones(zones)
          row.save!
          # The zone distribution is one of the summary's facts.
          Workouts::SummaryRefresh.schedule(row.workout)
        end
      end
    end

    private

    def stale_under(scope, zones)
      scope.where(zones_fingerprint: nil).or(scope.where.not(zones_fingerprint: zones.fingerprint))
    end
  end
end
