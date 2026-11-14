# frozen_string_literal: true

module Allure
  module HeartRate
    # Seconds spent at each whole bpm of a recording (PLAN_HEART_RATE.md §3.3).
    # Zones are sliced from it at read time, so changing a threshold never
    # re-reads a point. Reads recording segments through the PointSerializer
    # keys: the analyzer's in-memory segment metrics and the stored track
    # segments answer the same `points`. Pure and linear; no Active Record.
    #
    # Each reading in range credits the time to the next point, capped, to its
    # bpm; the last point of a segment credits nothing. Readings outside the
    # plausible range and values a losing strap held (FrozenRuns) are not
    # readings: they are skipped, never corrected.
    #
    # Three durations describe what the histogram stands on:
    # - `recorded_seconds`: first to last point of each segment, pauses inside
    #   a segment included;
    # - `covered_seconds`: every interval between two points, capped like a
    #   reading — the time the device actually recorded, pauses excluded;
    # - `sampled_seconds`: the part of it credited to a heart rate.
    # Coverage is sampled over covered: it says how much of the recorded time
    # carried a heart rate, whatever the pauses. A recording whose points are
    # mostly further apart than the cap is `sparse`: its few readings cannot
    # be spread over the time between them.
    class Histogram
      VERSION = 2
      RANGE = Allure::Gpx::Anomalies::HR_RANGE
      BINS = RANGE.size
      MAX_INTERVAL = 30.0
      MIN_COVERAGE = 0.5
      # Under this coverage the zone tab says how much was recorded.
      FULL_COVERAGE = 0.95

      Result = Data.define(:histogram, :sampled_seconds, :recorded_seconds, :covered_seconds,
                           :frozen_seconds, :sparse) do
        def empty? = sampled_seconds.zero?

        def coverage
          return 0.0 unless covered_seconds.positive?

          [ sampled_seconds.to_f / covered_seconds, 1.0 ].min
        end

        def usable? = !empty? && !sparse && coverage >= MIN_COVERAGE

        # Why a recording holding heart rate gives no zones: `:sparse` or
        # `:partial`; nil when usable or empty.
        def unusable_reason
          return nil if empty? || usable?

          sparse ? :sparse : :partial
        end
      end

      def self.bpm_for(index) = RANGE.begin + index

      def self.compute(segments)
        bins = Array.new(BINS, 0.0)
        recorded = 0.0
        covered = 0.0
        frozen_seconds = 0.0
        intervals = 0
        long_intervals = 0

        Array(segments).each do |segment|
          points = Array(segment.points)
          next if points.empty?

          times = points.map { time_of(it) }
          first_time = times.first
          last_time = times.last
          recorded += last_time - first_time if first_time && last_time && last_time > first_time
          frozen = FrozenRuns.indexes(points.map { rate_of(it) }, times)

          points.each_index do |index|
            following = index + 1
            break if following >= points.length

            start = times[index]
            finish = times[following]
            next unless start && finish

            interval = finish - start
            next unless interval.positive?

            credit = [ interval, MAX_INTERVAL ].min
            covered += credit
            intervals += 1
            long_intervals += 1 if interval > MAX_INTERVAL

            bpm = bpm_of(points[index])
            next unless bpm

            if frozen.include?(index)
              frozen_seconds += credit
            else
              bins[bpm - RANGE.begin] += credit
            end
          end
        end

        histogram = bins.map(&:round)
        Result.new(histogram:, sampled_seconds: histogram.sum, recorded_seconds: recorded.round,
                   covered_seconds: covered.round, frozen_seconds: frozen_seconds.round,
                   sparse: intervals.positive? && long_intervals * 2 > intervals)
      end

      def self.time_of(point)
        value = point[Allure::Gpx::PointSerializer::KEY_TIME]
        value.to_f if value.is_a?(Numeric)
      end

      # The raw reading as the anomaly pass sees it: any positive number.
      def self.rate_of(point)
        value = point[Allure::Gpx::PointSerializer::KEY_HEART_RATE]
        value if value.is_a?(Numeric) && value.finite? && value.positive?
      end

      def self.bpm_of(point)
        value = rate_of(point)
        return nil unless value

        bpm = value.round
        RANGE.cover?(bpm) ? bpm : nil
      end

      private_class_method :time_of, :rate_of, :bpm_of
    end
  end
end
