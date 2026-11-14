# frozen_string_literal: true

module Allure
  module Gpx
    # Rejects GPS positions that no plausible movement could produce. Two
    # deterministic stages run before any metric is derived:
    #
    # 1. interior displacement: a point whose detour through it is both far
    #    longer than the direct chord between its neighbours and long in
    #    absolute terms is an out-and-back spike;
    # 2. edge trim: a cold first fix or a stale final fix produces a run of
    #    impossible speeds at the start or the end of a recording. The speed
    #    envelope is derived from the track itself, so walking, running, and
    #    cycling are all covered without a per-sport table.
    #
    # Rejected points are removed, never repaired: the path between their
    # surviving neighbours becomes the recorded path, and the timestamps of
    # the survivors are unchanged.
    #
    # See PLAN_M1.md section 8.9 for the locked contract.
    module Outliers
      INTERIOR_MARGIN_METRES = 10.0
      INTERIOR_RATIO = 2.5
      INTERIOR_MAX_DURATION_SECONDS = 30.0

      EDGE_FLOOR_KM_H = 15.0
      EDGE_P90_FACTOR = 2.5
      EDGE_MEDIAN_FACTOR = 4.0

      module_function

      def filter(points)
        trim_implausible_edges(reject_interior_spikes(points))
      end

      # Removes the leftmost displaced point first, so a cluster of spikes is
      # reduced against its surviving neighbours rather than against points
      # that are themselves about to disappear. The kept prefix never holds a
      # spike, so only the triple ending at each new point, and those exposed
      # by a removal, need checking: one linear pass with the same result as
      # rescanning from the start after every removal.
      def reject_interior_spikes(points)
        kept = []
        points.each do |point|
          kept << point
          kept.delete_at(-2) while kept.length >= 3 && interior_spike?(kept[-3], kept[-2], kept[-1])
        end

        kept
      end

      def interior_spike?(previous_point, point, following_point)
        return false unless previous_point.time && point.time && following_point.time
        return false if following_point.time - previous_point.time > INTERIOR_MAX_DURATION_SECONDS

        detour = horizontal(previous_point, point) + horizontal(point, following_point)
        direct = horizontal(previous_point, following_point)
        detour - direct > INTERIOR_MARGIN_METRES && detour > direct * INTERIOR_RATIO
      end

      # Leading and trailing points whose adjacent interval exceeds the
      # track's own plausible speed envelope are cold-fix or stale-fix
      # artifacts. At least three points always survive.
      def trim_implausible_edges(points)
        return points if points.length < 3

        intervals = interval_speeds_km_h(points)
        cap = edge_speed_cap(intervals)

        first = 0
        first += 1 while first < points.length - 2 && exceeds_cap?(intervals[first], cap)

        last = points.length - 1
        last -= 1 while last > first + 1 && exceeds_cap?(intervals[last - 1], cap)

        points[first..last]
      end

      # Each entry is `[speed_km_h, duration_seconds]` for one interval, or
      # +nil+ when the interval has no positive duration.
      def interval_speeds_km_h(points)
        points.each_cons(2).map do |previous_point, current_point|
          next unless previous_point.time && current_point.time

          duration = current_point.time - previous_point.time
          next unless duration.positive?

          [ horizontal(previous_point, current_point) / duration * 3.6, duration ]
        end
      end

      # The envelope is data-driven: a slow activity (walking, hiking) gets a
      # low cap while a fast one keeps genuine descents. The median term keeps
      # a single fast interval from raising the cap on a short track.
      def edge_speed_cap(intervals)
        measured = intervals.compact
        return EDGE_FLOOR_KM_H if measured.empty?

        speeds = measured.map(&:first)
        [
          EDGE_FLOOR_KM_H,
          EDGE_P90_FACTOR * duration_weighted_percentile(measured, 0.9),
          EDGE_MEDIAN_FACTOR * median(speeds)
        ].max
      end

      def duration_weighted_percentile(intervals, fraction)
        total = intervals.sum { |_speed, duration| duration }
        return 0.0 if total <= 0

        target = total * fraction
        accumulated = 0.0
        intervals.sort_by { |speed, _duration| speed }.each do |speed, duration|
          accumulated += duration
          return speed if accumulated >= target
        end

        intervals.map(&:first).max
      end

      def exceeds_cap?(interval, cap)
        return false if interval.nil?

        interval.first > cap
      end

      def median(values)
        sorted = values.sort
        middle = sorted.length / 2
        return sorted[middle] if sorted.length.odd?

        (sorted[middle - 1] + sorted[middle]) / 2.0
      end

      def horizontal(first, second)
        Geo.horizontal_distance(first.latitude, first.longitude, second.latitude, second.longitude)
      end
    end
  end
end
