# frozen_string_literal: true

module Allure
  module Stats
    # A robust trend through a scatter of values over time, fitted at every
    # given x. Under LOWESS_MIN_POINTS points it is the Theil–Sen line (the
    # median of the pairwise slopes, Theil 1950, Sen 1968); from there it is
    # Cleveland's robust LOWESS (1979): a locally linear fit, so the ends are
    # not flattened and irregular spacing is respected (Fan & Gijbels 1996),
    # weighted by the tricube of the distance and reweighted by the bisquare
    # of the residuals so an outlier barely moves it. The neighbourhood is the
    # usual two thirds of the points, capped at MAX_NEIGHBOURS so a long
    # history still follows its seasons. `xs` must be sorted ascending; no
    # Active Record, plain floats in and out.
    module RobustTrend
      LOWESS_MIN_POINTS = 8
      SPAN = 2/3r
      MAX_NEIGHBOURS = 30
      ROBUSTNESS_ITERATIONS = 2
      # Points closer than this fraction of the x range share an interpolated
      # fit instead of their own (R's `lowess` delta), which keeps a history of
      # hundreds of outings to about a hundred local fits per pass.
      DELTA_FRACTION = 0.01

      module_function

      def fit(xs, ys)
        raise ArgumentError, "xs and ys differ in size" unless xs.size == ys.size

        xs = xs.map(&:to_f)
        ys = ys.map(&:to_f)
        xs.size < LOWESS_MIN_POINTS ? theil_sen(xs, ys) : lowess(xs, ys)
      end

      # The same trend evaluated at arbitrary positions (`at`, any order), so a
      # chart can draw it on a regular grid instead of only under the points:
      # a spline drawn through irregularly spaced fits overshoots, and can even
      # run backwards, beside a long gap. The LOWESS robustness weights are the
      # ones the data earned; each position gets its own local fit.
      def fit_at(xs, ys, at)
        raise ArgumentError, "xs and ys differ in size" unless xs.size == ys.size
        return [] if xs.empty?

        xs = xs.map(&:to_f)
        ys = ys.map(&:to_f)
        at = at.map(&:to_f)
        if xs.size < LOWESS_MIN_POINTS
          slope, intercept = theil_sen_line(xs, ys)
          return at.map { |x| intercept + slope * x }
        end

        neighbours = lowess_neighbours(xs.size)
        robustness = lowess_robustness(xs, ys, neighbours)
        range = xs.last - xs.first
        at.map do |x|
          left, right = nearest_window(xs, x, neighbours)
          local_fit(xs, ys, x, left, right, robustness, range)
        end
      end

      def theil_sen(xs, ys)
        return [] if xs.empty?

        slope, intercept = theil_sen_line(xs, ys)
        xs.map { |x| intercept + slope * x }
      end

      def theil_sen_line(xs, ys)
        slopes = []
        xs.each_index do |i|
          (i + 1...xs.size).each do |j|
            slopes << (ys[j] - ys[i]) / (xs[j] - xs[i]) unless xs[j] == xs[i]
          end
        end
        return [ 0.0, median(ys) ] if slopes.empty?

        slope = median(slopes)
        [ slope, median(xs.each_index.map { |i| ys[i] - slope * xs[i] }) ]
      end

      def lowess(xs, ys)
        neighbours = lowess_neighbours(xs.size)
        smooth(xs, ys, neighbours, lowess_robustness(xs, ys, neighbours))
      end

      def lowess_neighbours(size)
        [ (SPAN * size).ceil, MAX_NEIGHBOURS, size ].min
      end

      # The bisquare weights after the robustness iterations: an outlier ends
      # with a weight near zero. The final fit uses them.
      def lowess_robustness(xs, ys, neighbours)
        robustness = Array.new(xs.size, 1.0)
        tolerance = 1e-7 * ys.sum(&:abs) / ys.size

        ROBUSTNESS_ITERATIONS.times do
          fitted = smooth(xs, ys, neighbours, robustness)
          residuals = ys.each_index.map { |i| ys[i] - fitted[i] }
          scale = median(residuals.map(&:abs))
          break if scale <= tolerance

          robustness = residuals.map do |residual|
            u = residual / (6 * scale)
            u.abs < 1 ? (1 - u**2)**2 : 0.0
          end
        end
        robustness
      end

      # The `neighbours` points nearest to x, as an index range of sorted xs.
      def nearest_window(xs, x, neighbours)
        right = xs.bsearch_index { |value| value >= x } || xs.size
        left = right - 1
        neighbours.times do
          if left.negative?
            right += 1
          elsif right >= xs.size || x - xs[left] <= xs[right] - x
            left -= 1
          else
            right += 1
          end
        end
        [ left + 1, right - 1 ]
      end

      def smooth(xs, ys, neighbours, robustness)
        size = xs.size
        range = xs.last - xs.first
        delta = DELTA_FRACTION * range
        fitted = Array.new(size)
        left = 0
        previous = nil
        index = 0

        loop do
          # The window [left, left + neighbours) holds the nearest points; with
          # xs sorted it only ever moves right.
          left += 1 while left + neighbours < size && xs[index] - xs[left] > xs[left + neighbours] - xs[index]
          fitted[index] = local_fit(xs, ys, xs[index], left, left + neighbours - 1, robustness, range)
          interpolate(xs, fitted, previous, index) if previous && index - previous > 1
          break if index == size - 1

          previous = index
          following = index + 1
          following += 1 while following < size && xs[following] <= xs[index] + delta
          index = [ following - 1, index + 1 ].max
        end
        fitted
      end

      def local_fit(xs, ys, x, left, right, robustness, range)
        radius = [ x - xs[left], xs[right] - x ].max
        weights = (left..right).map do |j|
          distance = (xs[j] - x).abs
          tricube = radius.zero? ? 1.0 : (1 - (distance / radius)**3)**3
          [ tricube, 0.0 ].max
        end
        combined = weights.each_with_index.map { |weight, offset| weight * robustness[left + offset] }
        combined = weights if combined.sum <= 0

        total = combined.sum
        mean_x = combined.each_with_index.sum { |weight, offset| weight * xs[left + offset] } / total
        mean_y = combined.each_with_index.sum { |weight, offset| weight * ys[left + offset] } / total
        spread = combined.each_with_index.sum { |weight, offset| weight * (xs[left + offset] - mean_x)**2 }
        return mean_y unless Math.sqrt(spread / total) > 0.001 * range

        covariance = combined.each_with_index.sum do |weight, offset|
          weight * (xs[left + offset] - mean_x) * (ys[left + offset] - mean_y)
        end
        mean_y + (covariance / spread) * (x - mean_x)
      end

      def interpolate(xs, fitted, from, to)
        span = xs[to] - xs[from]
        (from + 1...to).each do |k|
          fitted[k] = span.zero? ? fitted[from] : fitted[from] + (xs[k] - xs[from]) / span * (fitted[to] - fitted[from])
        end
      end

      def median(values)
        sorted = values.sort
        middle = sorted.size / 2
        sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
      end
    end
  end
end
