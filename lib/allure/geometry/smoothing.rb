# frozen_string_literal: true

module Allure
  module Geometry
    # Display-time smoothing of an already-unwrapped polyline. It answers one
    # problem: a GPS trace recorded at one sample per second carries a few
    # metres of lateral jitter, so a track drawn zoomed-in looks hairy. A
    # distance-window moving average removes that jitter without redrawing the
    # route.
    #
    # The transform is deliberately display-only and **point-count preserving**:
    # consumers carry per-point metrics aligned by index (distance, elevation,
    # speed), and the map synchronises hover, selection and the colour ramp on
    # the same index. Cutting or adding points would silently misalign them, so
    # every input point maps to exactly one output point.
    #
    # The window is expressed in metres, like `Allure::Gpx::Elevation`'s filter,
    # so a 1 Hz watch and a smart-recording device see the same smoothing, and a
    # coarse track whose samples are farther apart than the window is left
    # untouched rather than flattened. The kernel is triangular and symmetric,
    # endpoints are fixed, and the window is capped in samples so a stationary
    # recording cannot make the filter quadratic.
    #
    # Callers must pass longitudes already made continuous (antimeridian
    # unwrapped); the average is a plain coordinate average, valid at the few
    # metres a window spans.
    module Smoothing
      HALF_WINDOW_METRES = { light: 10.0, medium: 25.0, strong: 40.0 }.freeze
      LEVELS = HALF_WINDOW_METRES.keys.map(&:to_s).freeze
      MAX_WINDOW_SAMPLES = 61

      module_function

      # Rejects an unknown level so a typo can never silently disable or
      # strengthen the display transform.
      def valid_level?(level)
        LEVELS.include?(level.to_s)
      end

      # Returns a new array with the same length as `coordinates`. A polyline
      # of fewer than three points, or one with no length, is returned as a
      # copy unchanged.
      def smooth(coordinates, level: :medium)
        points = normalize(coordinates)
        raise ArgumentError, "unknown smoothing level" unless valid_level?(level)
        return points.map(&:dup) if points.length < 3

        half_window = HALF_WINDOW_METRES.fetch(level.to_sym)
        lengths = cumulative_lengths(points)
        return points.map(&:dup) unless lengths.last.positive?

        max_side = (MAX_WINDOW_SAMPLES - 1) / 2
        smoothed = points.map.with_index do |point, index|
          next [ point[0], point[1] ] if index.zero? || index == points.length - 1

          window_mean(points, lengths, index, half_window, max_side) || [ point[0], point[1] ]
        end

        smoothed
      end

      def normalize(coordinates)
        Array(coordinates).map do |coordinate|
          values = Array(coordinate)
          raise ArgumentError, "invalid coordinate" unless values.length == 2

          longitude = Float(values[0])
          latitude = Float(values[1])
          unless longitude.finite? && latitude.finite?
            raise ArgumentError, "invalid coordinate"
          end

          [ longitude, latitude ]
        rescue TypeError, ArgumentError
          raise ArgumentError, "invalid coordinate"
        end
      end

      def cumulative_lengths(points)
        lengths = [ 0.0 ]
        points.each_cons(2) do |first, second|
          lengths << lengths.last + Allure::Gpx::Geo.horizontal_distance(first[1], first[0], second[1], second[0])
        end
        lengths
      end

      # Triangular weighted mean over the distance window, symmetric around the
      # point and bounded in sample count. Returns nil when the accumulated
      # weight is not positive, which leaves the point untouched.
      def window_mean(points, lengths, index, half_window, max_side)
        left = [ index - max_side, 0 ].max
        right = [ index + max_side, lengths.length - 1 ].min
        total = 0.0
        longitude = 0.0
        latitude = 0.0

        (left..right).each do |position|
          span = (lengths[position] - lengths[index]).abs
          next if span > half_window

          weight = 1.0 - (span / half_window)
          total += weight
          longitude += points[position][0] * weight
          latitude += points[position][1] * weight
        end

        return nil unless total.positive?

        [ longitude / total, latitude / total ]
      end
      private_class_method :window_mean
    end
  end
end
