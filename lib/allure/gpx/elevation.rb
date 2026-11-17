# frozen_string_literal: true

module Allure
  module Gpx
    # Elevation validity, noise filtering, and ascent/descent aggregation.
    # See docs/dev/WORKOUT.md for the locked algorithm.
    #
    # GPS elevation is the least accurate channel of a track: at 1 Hz it
    # jitters by roughly a metre, and summing raw positive deltas inflates
    # ascent several-fold. The canonical profile is therefore built from a
    # distance-window median (isolated spikes) followed by a distance-window
    # moving average (broadband noise). Windows are expressed in metres so a
    # 1 Hz watch and a smart-recording device see the same terrain, and a
    # coarse track whose samples are farther apart than the window is left
    # untouched rather than flattened.
    #
    # Ascent and descent are then accumulated with a threshold: an excursion
    # is counted only once its net change reaches the threshold, and the whole
    # excursion is added when it does. The threshold is selected by the
    # detected noise class: clean barometric profiles count small rolls with a
    # light filter, while GPS-derived profiles need a heavier filter and a
    # larger, noise-clearing change.
    module Elevation
      MINIMUM_VALID = -9999.99
      MAXIMUM_VALID = 9999.99

      MEDIAN_HALF_WINDOW_METRES = 8.0
      AVERAGE_HALF_WINDOW_METRES = { barometric: 20.0, gps: 40.0, dem: 80.0 }.freeze
      NOISE_HALF_WINDOW_METRES = 10.0

      # A stationary recording can pack thousands of samples inside a
      # distance window. The cap bounds the filter cost; the window becomes
      # trailing only in that already-flat case.
      MAX_WINDOW_SAMPLES = 61

      # Mean absolute deviation of a normal distribution is
      # `sigma * sqrt(2 / pi)`, so the reciprocal recovers sigma.
      MEAN_ABSOLUTE_DEVIATION_FACTOR = 1.2533
      BAROMETRIC_SIGMA_METRES = 0.35
      BAROMETRIC_THRESHOLD_METRES = 1.0
      GPS_THRESHOLD_METRES = 3.0
      # A coarse DEM has several metres of short-wavelength error; accumulating
      # it over a long route inflates ascent. Strava documents 10 m for
      # DEM-derived elevation; Allure keeps 8 m with a wide smoothing window.
      DEM_THRESHOLD_METRES = 8.0

      module_function

      # `0.0` is a valid elevation; only out-of-range or non-finite values are
      # treated as missing.
      def valid?(elevation)
        !elevation.nil? && elevation.finite? && elevation > MINIMUM_VALID && elevation < MAXIMUM_VALID
      end

      def minimum(elevations) = valid_values(elevations).min
      def maximum(elevations) = valid_values(elevations).max

      # Returns the canonical filtered profile, aligned with the input. Missing
      # values stay missing and are never bridged. `distances` is the
      # cumulative distance in metres for each point of the same series.
      def filter(elevations, distances:, noise_class: :gps)
        filtered = Array.new(elevations.length)
        average_half_window = AVERAGE_HALF_WINDOW_METRES.fetch(noise_class, AVERAGE_HALF_WINDOW_METRES[:gps])

        each_valid_run_indexed(elevations) do |run, indexes|
          run_distances = indexes.map { |index| distances[index] }
          medians = windowed_median(run, run_distances, MEDIAN_HALF_WINDOW_METRES)
          averaged = windowed_mean(medians, run_distances, average_half_window)
          indexes.each_with_index { |index, position| filtered[index] = averaged[position] }
        end

        filtered
      end

      # Robust estimate of the high-frequency elevation noise, pooled across
      # contiguous valid runs. Terrain that varies over tens of metres is not
      # noise: the window is short enough to see only the jitter.
      def noise_sigma(elevations, distances:)
        residuals = []

        each_valid_run_indexed(elevations) do |run, indexes|
          run_distances = indexes.map { |index| distances[index] }
          medians = windowed_median(run, run_distances, NOISE_HALF_WINDOW_METRES)
          run.each_with_index { |value, position| residuals << (value - medians[position]).abs }
        end

        return 0.0 if residuals.empty?

        MEAN_ABSOLUTE_DEVIATION_FACTOR * residuals.sum / residuals.length
      end

      # `:barometric` for a clean profile, `:gps` for a noisy one.
      def noise_class(elevations, distances:)
        noise_sigma(elevations, distances:) < BAROMETRIC_SIGMA_METRES ? :barometric : :gps
      end

      # Accepts the symbol used by the analyzer and the string persisted on
      # `workouts.elevation_filter`; an unknown or missing class is the
      # conservative GPS threshold.
      def threshold_for(noise_class)
        case noise_class.to_s
        when "barometric" then BAROMETRIC_THRESHOLD_METRES
        when "dem" then DEM_THRESHOLD_METRES
        else GPS_THRESHOLD_METRES
        end
      end

      # Returns `[ascent, descent]` in metres. Splits the input into
      # contiguous runs of valid elevation and accumulates each run
      # independently, never bridging a missing value with an artificial
      # climb. The input must already be the canonical filtered profile; this
      # method never smooths again.
      def ascent_and_descent(elevations, threshold: GPS_THRESHOLD_METRES)
        ascent = 0.0
        descent = 0.0

        each_valid_run(elevations) do |run|
          pending = 0.0
          run.each_cons(2) do |previous, current|
            pending += current - previous
            if pending >= threshold
              ascent += pending
              pending = 0.0
            elsif pending <= -threshold
              descent += -pending
              pending = 0.0
            end
          end
        end

        [ ascent, descent ]
      end

      def valid_values(elevations) = elevations.select { |elevation| valid?(elevation) }

      def each_valid_run(elevations)
        run = []
        elevations.each do |elevation|
          if valid?(elevation)
            run << elevation
          elsif run.any?
            yield run
            run = []
          end
        end
        yield run if run.any?
      end

      # Yields each contiguous valid run together with the original indexes of
      # its points, so distance windows can be resolved on the source series.
      def each_valid_run_indexed(elevations)
        run = []
        indexes = []
        elevations.each_with_index do |elevation, index|
          if valid?(elevation)
            run << elevation
            indexes << index
          elsif run.any?
            yield run, indexes
            run = []
            indexes = []
          end
        end
        yield run, indexes if run.any?
      end

      def windowed_median(values, distances, half_window)
        length = values.length
        left = 0
        right = 0
        result = Array.new(length)

        length.times do |index|
          right += 1 while right < length && distances[right] - distances[index] <= half_window
          left += 1 while left < index && distances[index] - distances[left] > half_window
          left = right - MAX_WINDOW_SAMPLES if right - left > MAX_WINDOW_SAMPLES
          result[index] = median(values[left...right])
        end

        result
      end

      def windowed_mean(values, distances, half_window)
        length = values.length
        left = 0
        right = 0
        sum = 0.0
        result = Array.new(length)

        length.times do |index|
          while right < length && distances[right] - distances[index] <= half_window
            sum += values[right]
            right += 1
          end
          while left < index && distances[index] - distances[left] > half_window
            sum -= values[left]
            left += 1
          end
          while right - left > MAX_WINDOW_SAMPLES
            sum -= values[left]
            left += 1
          end
          result[index] = sum / (right - left)
        end

        result
      end

      def median(values)
        sorted = values.sort
        middle = sorted.length / 2
        return sorted[middle].to_f if sorted.length.odd?

        (sorted[middle - 1] + sorted[middle]) / 2.0
      end
    end
  end
end
