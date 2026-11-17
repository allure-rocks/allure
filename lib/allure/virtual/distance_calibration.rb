# frozen_string_literal: true

module Allure
  module Virtual
    # Fits a virtual platform's rendered positions to the distance the
    # ergometer itself recorded (docs/dev/VIRTUAL-PLATFORMS.md). A virtual world's
    # coordinates are drawn, not measured: EXR's Bled race course places the
    # boat at twice its real distance, and every world drifts by a few
    # percent. The file's lap distances are the athlete's real effort, so they
    # are authoritative.
    #
    # The analyzer's outlier filter runs first: EXR often snaps its last
    # record to the finish line, a jump the analyzer would drop with the
    # distance it carries. Each surviving point keeps its time and signals and
    # is moved along its own recording segment to the position matching its
    # scaled cumulative distance, so the map follows the course and every
    # metric derived from the points (distance, speed, pace, splits, best
    # efforts) agrees with the recorded distance. A position beyond the drawn
    # end of a segment is extended along its last direction. Resampled points
    # cut the corners of EXR's quantized zigzag, so a last pass scales every
    # step vector by the small remaining ratio, which is exact.
    #
    # Fail-closed: without laps covering the recording, or with a ratio
    # outside RATIO_RANGE, the segments are returned unchanged.
    module DistanceCalibration
      # The laps must account for this share of the recording span, so a
      # missing final lap never shrinks the whole track.
      MIN_LAP_COVERAGE = 0.9
      RATIO_RANGE = (0.25..4.0)
      # Close enough to the recorded distance: 1 cm over 10 km.
      TOLERANCE = 1e-6

      module_function

      def call(segments:, laps:)
        # A positionless recording has no drawn course to fit; its distance
        # already comes from the device (docs/dev/NO-GPS.md).
        return segments unless segments.all?(&:positioned?)

        cleaned = segments.map { |segment| Allure::Gpx::Outliers.filter(segment.points) }
        ratio = ratio(cleaned, laps)
        return segments if ratio.nil?

        cleaned = cleaned.map { |points| rescale(points, ratio) }
        remaining = ratio(cleaned, laps)
        cleaned = cleaned.map { |points| scale_steps(points, remaining) } if remaining

        cleaned.map { |points| Allure::Gpx::Segment.new(points:) }
      end

      # Nil when the drawn distance needs no correction or cannot be trusted.
      def ratio(segments, laps)
        recorded = laps.sum { |lap| lap.distance.to_f }
        return nil unless recorded.positive?
        return nil unless laps_cover?(segments, laps)

        drawn = segments.sum { |points| cumulative_distances(points).last }
        return nil unless drawn.positive?

        ratio = recorded / drawn
        return nil unless RATIO_RANGE.cover?(ratio)
        return nil if (ratio - 1.0).abs < TOLERANCE

        ratio
      end

      def laps_cover?(segments, laps)
        first = segments.first&.first
        last = segments.last&.last
        return false unless first && last

        span = last.time - first.time
        return true unless span.positive?

        laps.sum(&:elapsed_time) >= span * MIN_LAP_COVERAGE
      end

      def cumulative_distances(points)
        total = 0.0
        points.each_with_index.map do |point, index|
          total += step(points[index - 1], point) if index.positive?
          total
        end
      end

      def rescale(points, ratio)
        cumulative = cumulative_distances(points)
        return points unless cumulative.last.positive?

        edge = 0
        points.each_with_index.map do |point, index|
          target = cumulative[index] * ratio
          edge += 1 while edge < points.length - 2 && cumulative[edge + 1] < target
          latitude, longitude = position_at(points, cumulative, edge, target)
          point.with(latitude:, longitude:)
        end
      end

      # Keeps the first point and lengthens every step by `ratio`: the shape
      # is preserved at a scale that only a small residual ratio leaves
      # imperceptible.
      def scale_steps(points, ratio)
        latitude = points.first.latitude
        longitude = points.first.longitude
        points.each_with_index.map do |point, index|
          if index.positive?
            previous = points[index - 1]
            latitude += (point.latitude - previous.latitude) * ratio
            longitude += Allure::Gpx::Geo.normalize_longitude_delta(point.longitude - previous.longitude) * ratio
          end
          point.with(latitude:, longitude: Allure::Gpx::Geo.normalize_longitude_delta(longitude))
        end
      end

      # Interpolates on edge `index`; past the drawn end, the last edge of
      # non-zero length gives the direction.
      def position_at(points, cumulative, index, target)
        index -= 1 while index.positive? && cumulative[index + 1] <= cumulative[index]
        from = points[index]
        to = points[index + 1]
        length = cumulative[index + 1] - cumulative[index]
        # Only a stationary start reaches here: the target is that start.
        return [ from.latitude, from.longitude ] unless length.positive?

        fraction = (target - cumulative[index]) / length

        longitude = from.longitude + (Allure::Gpx::Geo.normalize_longitude_delta(to.longitude - from.longitude) * fraction)
        [
          from.latitude + ((to.latitude - from.latitude) * fraction),
          Allure::Gpx::Geo.normalize_longitude_delta(longitude)
        ]
      end

      def step(from, to)
        Allure::Gpx::Geo.horizontal_distance(from.latitude, from.longitude, to.latitude, to.longitude)
      end
    end
  end
end
