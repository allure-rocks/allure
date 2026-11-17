# frozen_string_literal: true

# A recording's seconds-per-bpm histogram and what it gives under the owner's
# current zones (docs/dev/HEART-RATE.md). Owner-only: never in a snapshot, a
# Note, a credit row or a webhook payload.
class WorkoutHeartRate < ApplicationRecord
  belongs_to :workout, inverse_of: :heart_rate

  # The SQL twin of Histogram::Result#usable?: some heart rate, points close
  # enough, and a heart rate over at least MIN_COVERAGE of the recorded time.
  scope :usable, lambda {
    where("workout_heart_rates.sampled_seconds > 0").where(sparse: false)
      .where("workout_heart_rates.sampled_seconds >= CAST(? AS numeric) * workout_heart_rates.covered_seconds",
             Allure::HeartRate::Histogram::MIN_COVERAGE)
  }
  # Usable, but with a heart rate over only part of the recorded time.
  scope :partial, lambda {
    usable.where("workout_heart_rates.sampled_seconds < CAST(? AS numeric) * workout_heart_rates.covered_seconds",
                 Allure::HeartRate::Histogram::FULL_COVERAGE)
  }

  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates :sampled_seconds, :recorded_seconds, :covered_seconds, :frozen_seconds,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :histogram_shape
  validate :zone_seconds_shape
  validate :recording_only

  def result
    Allure::HeartRate::Histogram::Result.new(histogram:, sampled_seconds:, recorded_seconds:, covered_seconds:,
                                             frozen_seconds:, sparse:)
  end

  delegate :coverage, :usable?, :unusable_reason, to: :result

  # Stored seconds when they were sliced under these zones, else sliced now:
  # a page is never wrong while HeartRates::RezoneJob catches up.
  def zone_seconds_for(zones)
    return nil unless zones
    return zone_seconds if zones_fingerprint == zones.fingerprint && zone_seconds

    zones.slice(histogram)
  end

  def load_for(zones)
    return nil unless zones
    return load.to_f if zones_fingerprint == zones.fingerprint && !load.nil?

    Allure::HeartRate::Load.edwards(histogram, zones)
  end

  # Writes the zone columns for the given zones, or clears them.
  def assign_zones(zones)
    if zones
      self.zone_seconds = zones.slice(histogram)
      self.load = Allure::HeartRate::Load.edwards(histogram, zones)
      self.zones_fingerprint = zones.fingerprint
    else
      self.zone_seconds = nil
      self.load = nil
      self.zones_fingerprint = nil
    end
  end

  private

  def histogram_shape
    return if histogram.is_a?(Array) && histogram.size == Allure::HeartRate::Histogram::BINS &&
              histogram.all? { it.is_a?(Integer) && !it.negative? }

    errors.add(:histogram, :invalid)
  end

  def zone_seconds_shape
    return if zone_seconds.nil? && zones_fingerprint.nil?
    return if zone_seconds.is_a?(Array) && zone_seconds.size == Allure::HeartRate::Zones::COUNT && zones_fingerprint.present?

    errors.add(:zone_seconds, :invalid)
  end

  def recording_only
    errors.add(:workout, :invalid) if workout && !workout.recording?
  end
end
