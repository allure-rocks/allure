# frozen_string_literal: true

module Allure
  module Gpx
    # Finds the best effort over a set of standard distances inside one
    # workout. Pure Ruby, framework-independent, and deterministic.
    #
    # Semantics (docs/dev/BEST-EFFORTS.md):
    # - an effort lives inside a single recording segment; a recording pause is
    #   never bridged;
    # - the measured time is elapsed time, stops included;
    # - boundaries are interpolated linearly to the exact distance, and both
    #   start-anchored and end-anchored windows are checked because the
    #   elapsed-time function is piecewise linear in the start distance.
    module BestEfforts
      Effort = Data.define(
        :distance_key,
        :distance_meters,
        :elapsed_seconds,
        :duration_seconds,
        :started_at,
        :start_offset_meters,
        :end_offset_meters
      )

      DISTANCES = {
        "m400" => 400.0,
        "m500" => 500.0,
        "half_mile" => 804.672,
        "km1" => 1_000.0,
        "mi1" => 1_609.344,
        "km2" => 2_000.0,
        "mi2" => 3_218.688,
        "km5" => 5_000.0,
        "km6" => 6_000.0,
        "km10" => 10_000.0,
        "km15" => 15_000.0,
        "mi10" => 16_093.44,
        "km20" => 20_000.0,
        "half_marathon" => 21_097.5,
        "km30" => 30_000.0,
        "marathon" => 42_195.0,
        "mi5" => 8_046.72,
        "km40" => 40_000.0,
        "km50" => 50_000.0,
        "km80" => 80_000.0,
        "mi50" => 80_467.2
      }.freeze

      PROFILES = {
        "run" => %w[
          m400 half_mile km1 mi1 mi2 km5 km10 km15 mi10 km20 half_marathon km30
          marathon
        ].freeze,
        "ride" => %w[
          mi5 km10 mi10 km20 km30 km40 km50 km80 mi50
        ].freeze,
        "row" => %w[
          m500 km1 km2 km5 km6 km10 half_marathon marathon
        ].freeze
      }.freeze

      SPORT_PROFILES = {
        "running" => "run",
        "running_virtual" => "run",
        "trail" => "run",
        "cycling" => "ride",
        "cycling_road" => "ride",
        "cycling_gravel" => "ride",
        "cycling_electric" => "ride",
        "cycling_virtual" => "ride",
        "cycling_trekking" => "ride",
        "mountain_biking" => "ride",
        "mountain_biking_electric" => "ride",
        "halfbike" => "ride",
        "rowing" => "row",
        "rowing_virtual" => "row"
      }.freeze

      module_function

      def profile_for(sport_slug) = SPORT_PROFILES[sport_slug.to_s]

      # Ordered `[key, metres]` pairs for the sport, or an empty array when the
      # sport has no effort profile.
      def distances_for(sport_slug)
        profile = profile_for(sport_slug)
        return [] unless profile

        PROFILES.fetch(profile).map { |key| [ key, DISTANCES.fetch(key) ] }
      end

      # Returns one best Effort per requested distance, in the requested order.
      # Distances no single recording segment can cover are omitted.
      def find(segments:, distances:, workout_started_at:)
        points = Allure::Segments::PointStream.new(segments:, workout_started_at:).call
        return [] if points.length < 2

        best = {}
        each_segment_run(points) do |segment_points|
          distances.each do |key, meters|
            effort = best_window(segment_points, key, meters.to_f)
            next unless effort

            existing = best[key]
            best[key] = effort if existing.nil? || better?(effort, existing)
          end
        end
        distances.filter_map { |key, _meters| best[key] }
      end

      def each_segment_run(points, &block)
        points.chunk_while { |previous, current| previous.segment_index == current.segment_index }.each(&block)
      end

      def best_window(points, key, meters)
        return nil if points.length < 2 || meters <= 0

        better_candidate(start_anchored(points, key, meters), end_anchored(points, key, meters))
      end

      # Windows whose start is a recorded point.
      def start_anchored(points, key, meters)
        count = points.length
        last_distance = points.last.distance.to_f
        best = nil
        j = 1

        (0...(count - 1)).each do |i|
          start_distance = points[i].distance.to_f
          break if last_distance - start_distance < meters

          j = i + 1 if j < i + 1
          j += 1 while j < count && points[j].distance.to_f - start_distance < meters
          break if j >= count

          target = start_distance + meters
          end_time = interpolate_time(points[j - 1], points[j], target)
          candidate = build_effort(key, meters, points[i].time, end_time, start_distance, target)
          best = better_candidate(best, candidate)
        end
        best
      end

      # Windows whose end is a recorded point.
      def end_anchored(points, key, meters)
        count = points.length
        first_distance = points[0].distance.to_f
        best = nil
        i = 0

        (1...count).each do |j|
          end_distance = points[j].distance.to_f
          target = end_distance - meters
          next if target < first_distance

          i += 1 while i + 1 < j && points[i + 1].distance.to_f <= target
          start_time = interpolate_time(points[i], points[i + 1], target)
          candidate = build_effort(key, meters, start_time, points[j].time, target, end_distance)
          best = better_candidate(best, candidate)
        end
        best
      end

      def build_effort(key, meters, start_time, end_time, start_offset, end_offset)
        elapsed = end_time - start_time
        return nil unless elapsed.positive?

        Effort.new(
          distance_key: key,
          distance_meters: meters,
          elapsed_seconds: elapsed,
          duration_seconds: elapsed.round,
          started_at: start_time,
          start_offset_meters: start_offset,
          end_offset_meters: end_offset
        )
      end

      def interpolate_time(first, second, target)
        first_distance = first.distance.to_f
        second_distance = second.distance.to_f
        return first.time if second_distance <= first_distance

        fraction = (target - first_distance) / (second_distance - first_distance)
        first.time + ((second.time - first.time) * fraction)
      end

      def better_candidate(current, candidate)
        return current unless candidate
        return candidate unless current
        return candidate if candidate.elapsed_seconds < current.elapsed_seconds
        return current if candidate.elapsed_seconds > current.elapsed_seconds

        candidate.started_at < current.started_at ? candidate : current
      end

      def better?(effort, existing)
        better_candidate(existing, effort).equal?(effort)
      end
    end
  end
end
