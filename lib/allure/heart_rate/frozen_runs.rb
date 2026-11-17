# frozen_string_literal: true

module Allure
  module HeartRate
    # The readings a strap held while losing its signal
    # (docs/dev/HEART-RATE.md): the same value repeated over at least HR_FROZEN_SAMPLES samples
    # and HR_FROZEN_SECONDS, followed by at least HR_FROZEN_FOLLOWING_SECONDS
    # without heart rate. The definition is the anomaly pass's `hr_frozen`
    # (Allure::Gpx::Anomalies), applied to one recording segment; the held
    # value is not a reading, so the histogram skips it.
    module FrozenRuns
      SAMPLES = Allure::Gpx::Anomalies::HR_FROZEN_SAMPLES
      SECONDS = Allure::Gpx::Anomalies::HR_FROZEN_SECONDS
      FOLLOWING_SECONDS = Allure::Gpx::Anomalies::HR_FROZEN_FOLLOWING_SECONDS

      module_function

      # `rates` and `times` are index-aligned: a positive number or nil, and
      # seconds (nil when the point has no time). Returns the frozen indexes.
      def indexes(rates, times)
        frozen = Set.new
        index = 0
        while index < rates.length
          rate = rates[index]
          last = index
          last += 1 while rate && last + 1 < rates.length && rates[last + 1] == rate
          if rate && last - index + 1 >= SAMPLES && span(times, index, last) >= SECONDS &&
             missing_after(rates, times, last) >= FOLLOWING_SECONDS
            (index..last).each { frozen << it }
          end
          index = last + 1
        end
        frozen
      end

      # The duration of the run without heart rate that follows `last`, up to
      # the next reading or to the end of the segment.
      def missing_after(rates, times, last)
        first = last + 1
        return 0.0 unless first < rates.length && rates[first].nil?

        stop = first
        stop += 1 while stop + 1 < rates.length && rates[stop + 1].nil?
        stop += 1 if stop + 1 < rates.length
        span(times, first, stop)
      end

      def span(times, first, last)
        return 0.0 unless times[first] && times[last]

        times[last] - times[first]
      end

      private_class_method :missing_after, :span
    end
  end
end
